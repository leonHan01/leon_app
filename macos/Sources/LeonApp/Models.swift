import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: Int64
    let clientMessageId: String
    let deviceId: String
    let sender: String
    let platform: String
    let text: String
    let createdAt: Int64
    let conversationId: String?
    let role: String?
    let agentId: String?
    let replyTo: Int64?
    var date: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }
}

struct MessagePage: Codable {
    let messages: [Message]
    let hasMore: Bool
    let jobs: [AgentJob]?
}

struct AgentInfo: Codable, Identifiable {
    let id: String
    let name: String
    let handle: String
    let provider: String
    let model: String
    let enabled: Bool
    let avatarId: String?
}
struct Conversation: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let agentId: String?
    let agentIds: [String]
}
struct AgentJob: Codable, Identifiable {
    var id: String { "\(messageId):\(agentId)" }
    let messageId: Int64
    let agentId: String
    let agentName: String
    let status: String
    let error: String
}

struct Outgoing: Codable, Identifiable {
    var id: String { clientMessageId }
    let clientMessageId: String
    let deviceId: String
    let sender: String
    let platform: String
    let text: String
    var conversationId: String? = nil
    var mentionAgentIds: [String]? = nil
}

enum Endpoint {
    static func normalize(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw ClientError.message("请输入 HTTPS 服务地址；本机开发可使用 http://127.0.0.1:8080。")
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        guard let normalized = components?.url else {
            throw ClientError.message("服务地址无效。")
        }
        return normalized
    }
}

enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

enum HTTPFailure {
    static func message(for status: Int) -> String? {
        switch status {
        case 401: return "访问令牌未通过认证，请检查令牌后重试。"
        case 403: return "服务器拒绝访问（HTTP 403）。请检查服务端接口权限或 HTTPS 代理配置。"
        case 404: return "服务端尚未安装消息接口，请先升级服务端。"
        case 502, 503, 504: return "服务暂时不可用（HTTP \(status)），请检查服务端运行状态。"
        default: return nil
        }
    }
}

// Credentials are never forwarded through a redirect, including redirects on the same host.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class MessageAPI: @unchecked Sendable {
    let base: URL
    private let token: String
    private let session: URLSession
    private let avatarCache = NSCache<NSString, NSData>()
    init(base: URL, token: String) {
        self.base = base
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        avatarCache.totalCostLimit = 8 * 1024 * 1024
    }
    deinit { session.invalidateAndCancel() }

    func page(conversation: String = "shared", after: Int64? = nil, before: Int64? = nil) async throws -> MessagePage {
        var components = URLComponents(url: base.appendingPathComponent("api/device-messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "conversationId", value: conversation)]
        if let after { components.queryItems?.append(URLQueryItem(name: "after", value: String(after))) }
        if let before { components.queryItems?.append(URLQueryItem(name: "before", value: String(before))) }
        return try await request(URLRequest(url: components.url!))
    }

    func agents() async throws -> [AgentInfo] { try await request(URLRequest(url: base.appendingPathComponent("api/agents"))) }
    func heartbeat(deviceId: String, name: String) async throws {
        struct Presence: Decodable { let lastSeenAt: Int64 }
        let _: Presence = try await post("api/device-messages/presence", body: ["deviceId": deviceId, "name": name, "platform": "macos"])
    }
    func avatarData(_ id: String) async throws -> Data {
        guard id.range(of: "^[a-z0-9-]{1,80}$", options: .regularExpression) != nil else { throw ClientError.message("头像标识无效") }
        if let cached = avatarCache.object(forKey: id as NSString) { return cached as Data }
        var req = URLRequest(url: base.appendingPathComponent("api/agent-avatars/\(id)"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType == "image/png", data.count <= 2 * 1024 * 1024 else { throw ClientError.message("头像暂时不可用") }
        avatarCache.setObject(data as NSData, forKey: id as NSString, cost: data.count)
        return data
    }
    func conversations() async throws -> [Conversation] { try await request(URLRequest(url: base.appendingPathComponent("api/conversations"))) }
    func direct(_ agentId: String) async throws -> Conversation { try await post("api/conversations/direct/\(agentId)", body: [String:String]()) }
    func group(name: String, agentIds: [String]) async throws -> Conversation {
        struct Group: Encodable { let name: String; let agentIds: [String] }
        return try await post("api/conversations/groups", body: Group(name: name, agentIds: agentIds))
    }
    func retryJob(_ job: AgentJob) async throws {
        struct Result: Decodable { let queued: Bool }
        let _: Result = try await post("api/device-messages/\(job.messageId)/agents/\(job.agentId)/retry", body: [String:String]())
    }
    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path)); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONEncoder().encode(body)
        return try await request(req)
    }

    func send(_ outgoing: Outgoing) async throws -> Message {
        var req = URLRequest(url: base.appendingPathComponent("api/device-messages"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(outgoing)
        return try await request(req)
    }

    private struct Failure: Decodable { let detail: String?; let message: String? }
    private func request<T: Decodable>(_ input: URLRequest) async throws -> T {
        var req = input
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("服务端没有返回有效响应。") }
        switch http.statusCode {
        case 200...299: return try JSONDecoder().decode(T.self, from: data)
        default:
            if let message = HTTPFailure.message(for: http.statusCode) { throw ClientError.message(message) }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw ClientError.message(failure?.detail ?? failure?.message ?? "请求失败（HTTP \(http.statusCode)），请稍后重试。")
        }
    }
}

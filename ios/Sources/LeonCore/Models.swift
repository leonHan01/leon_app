import Foundation

struct ChatUser: Codable, Equatable {
    let id: String
    let username: String
    var home: String { username.lowercased() == "leon" ? "shared" : "home:\(id)" }
}
struct LoginResult: Codable { let user: ChatUser; let sessionToken: String }
struct Credentials: Codable { let server: String; let user: ChatUser; let token: String }
struct ChatImage: Codable, Identifiable, Equatable {
    let id: String; let mimeType: String; let width: Int; let height: Int; let byteCount: Int
}
struct Message: Codable, Identifiable, Equatable {
    let id: Int64; let clientMessageId: String; let deviceId: String
    let sender: String; let platform: String; let text: String; let createdAt: Int64
    var conversationId: String?; var role: String?; var agentId: String?; var replyTo: Int64?
    var images: [ChatImage]?; var userId: String?
    var quote: MessageQuote? = nil
    var documents:[DocumentAttachment]? = nil
    var date: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }
}
extension Array where Element == Message {
    // A page usually falls entirely before or after the loaded history.
    func mergingMessagePage(_ page: [Message]) -> [Message]? {
        guard let firstIncoming = page.first, let lastIncoming = page.last else { return nil }
        if zip(page, page.dropFirst()).allSatisfy({ $0.0.id < $0.1.id }) {
            guard let first, let last else { return page }
            if firstIncoming.id > last.id { return self + page }
            if lastIncoming.id < first.id { return page + self }
        }

        // Preserve the latest value for each ID when pages overlap or arrive out of order.
        var byID = Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
        for message in page { byID[message.id] = message }
        let merged = byID.values.sorted { $0.id < $1.id }
        return merged == self ? nil : merged
    }
}

struct AgentInfo: Codable, Identifiable, Equatable {
    let id: String; let name: String; let handle: String; let provider: String
    let model: String?; let enabled: Bool; let avatarId: String?; let description: String?
}
struct Conversation: Codable, Identifiable, Equatable {
    let id: String; let name: String; let kind: String; let agentId: String?
    let agentIds: [String]; var ownerId: String?
    var direct: Bool { kind == "direct" }
}
struct AgentJob: Codable, Identifiable, Equatable {
    let messageId: Int64; let agentId: String; let agentName: String; let status: String
    let error: String; var userId: String?; var phase: String?
    var id: String { "\(messageId):\(agentId)" }
    var failed: Bool { status == "FAILED" }
    var dismissal: String { id + "#" + error }
    var progressText: String { failed ? error : (phase == "COMPRESSING" ? "上下文压缩中…" : status == "RUNNING" ? "正在回复…" : "等待回复…") }
}
struct ContextOperation: Codable, Identifiable, Equatable {
    let id: String; let agentId: String; let agentName: String; let status: String
    let error: String; let result: String; let createdAt: Int64; let kind: String?
    var progressText: String { status == "FAILED" ? error : status == "SUCCEEDED" ? result : "上下文压缩中…" }
}
struct MessagePage: Codable {
    let messages: [Message]; let hasMore: Bool; var jobs: [AgentJob]?
    var contextOperations: [ContextOperation]?; var historyRevision: Int64?
}
struct Outgoing: Codable, Identifiable, Equatable {
    var id: String { clientMessageId }
    let clientMessageId: String; let deviceId: String; let sender: String; let platform: String
    let text: String; let conversationId: String; var mentionAgentIds: [String] = []; var imageIds: [String] = []
    var quoteMessageId: Int64? = nil
    var documentIds:[String]? = nil
    var quote: MessageQuote? = nil
    var documents:[DocumentAttachment]? = nil
}
struct DraftImage: Identifiable, Equatable, Sendable { let id: String; let data: Data }
struct ImageOrigin: Equatable, Sendable { let connection: UUID; let room: String }
struct UserNotice: Identifiable, Equatable {let id = UUID();let text:String}
struct ModelUsage: Codable, Identifiable, Equatable {
    var id: String { provider + ":" + model }
    let provider: String; let model: String; let inputTokens: Int64; let outputTokens: Int64; let totalTokens: Int64
    let reportedCalls: Int64; let unreportedCalls: Int64; var firstRecordedAt: String?; var lastRecordedAt: String?
}
struct ConversationContext: Codable {
    let conversationId: String; let recentRounds: Int; let inputTokenBudget: Int; let topicStartedAfter: Int64
    let agents: [AgentContextInfo]
    var compressionMode: String? = nil
}
struct ContextFact: Codable, Identifiable {
    var id: String { subjectId + ":" + kind + ":" + key }
    let subjectId: String; let speaker: String; let kind: String; let key: String
    let value: String; let sourceMessageId: Int64
}
struct AgentContextInfo: Codable, Identifiable {
    var id: String { agentId }
    let agentId: String; let agentName: String; let summary: String
    let lastCompressedAt: Int64; let estimatedInputTokens: Int; let retainedRounds: Int; let phase: String
    var facts: [ContextFact]? = nil
    var retrievedRounds: Int? = nil
    var compressionFallback: Bool? = nil
}
struct ClearHistoryPreview: Codable {
    let conversationId: String; let conversationName: String; let messageCount: Int64
    let latestMessageId: Int64; let historyRevision: Int64; let hasActiveWork: Bool
}
struct ClearHistoryResult: Codable { let clearedMessages: Int64; let historyRevision: Int64 }
struct OutboxSnapshot: Codable {
    var pending: [Outgoing] = []; var dismissed: Set<String> = []; var revisions: [String:Int64] = [:]
    init(pending: [Outgoing] = [], dismissed: Set<String> = [], revisions: [String:Int64] = [:]) {self.pending = pending;self.dismissed = dismissed;self.revisions = revisions}
    enum CodingKeys: String,CodingKey {case pending,dismissed,revisions}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        pending = try values.decodeIfPresent([Outgoing].self,forKey:.pending) ?? []
        dismissed = try values.decodeIfPresent(Set<String>.self,forKey:.dismissed) ?? []
        revisions = try values.decodeIfPresent([String:Int64].self,forKey:.revisions) ?? [:]
    }
}
struct NativeError: LocalizedError {
    let message: String; var status: Int? = nil
    var errorDescription: String? { message }
    var expired: Bool { status == 401 }
}

enum Endpoint {
    static func normalize(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.port.map({ (1...65535).contains($0) }) ?? true,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        else { throw NativeError(message: "请输入 HTTPS 服务地址；本机开发可使用 http://127.0.0.1:8080。") }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path = ""; components.host = host.lowercased()
        return components.url!
    }
}


struct ChatSearchHit: Codable, Identifiable {
    let message: Message
    let conversationName: String
    var id: Int64 { message.id }
}
struct ChatSearchPage: Codable {
    let results: [ChatSearchHit]
    let hasMore: Bool
    let nextBefore: Int64?
}
struct ChatSearchContext: Codable {
    let messages: [Message]
    let hasOlder: Bool
    let hasNewer: Bool
    let historyRevision: Int64
}


struct MessageQuote: Codable, Identifiable, Equatable {
    let id: Int64
    let sender: String
    let text: String
    let images: [ChatImage]
    var documents:[DocumentAttachment]? = nil
    var preview: String { (images.isEmpty ? "" : "[图片] ") + ((documents ?? []).map {"[文件] "+$0.name}.joined(separator:" ")) + text.replacingOccurrences(of:"\n",with:" ") }
    init(message: Message) { id=message.id;sender=message.sender;text=message.text;images=message.images ?? [];documents=message.documents }
    init(id:Int64,sender:String,text:String,images:[ChatImage]) {self.id=id;self.sender=sender;self.text=text;self.images=images}
}
struct FavoriteItem: Codable, Identifiable, Equatable {
    let id: Int64
    let message: Message
    let conversationName: String
    let savedAt: Int64
}
struct FavoritePage: Codable {
    let results: [FavoriteItem]
    let hasMore: Bool
    let nextBefore: Int64?
}

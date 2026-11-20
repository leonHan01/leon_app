import Foundation

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
protocol ChatAPI: AnyObject, Sendable {
    func login(_ username: String) async throws -> LoginResult
    func logout() async throws
    func agents() async throws -> [AgentInfo]
    func conversations() async throws -> [Conversation]
    func heartbeat(deviceId: String, name: String) async throws
    func page(room: String, after: Int64?, before: Int64?) async throws -> MessagePage
    func search(query: String, room: String?, before: Int64?) async throws -> ChatSearchPage
    func searchContext(room: String, message: Int64, direction: String) async throws -> ChatSearchContext
    func direct(_ agent: String) async throws -> Conversation
    func newThread(agent: String, name: String, requestId: String) async throws -> Conversation
    func branch(room:String,message:Int64,name:String,requestId:String) async throws -> Conversation
    func group(name: String, agentIds: [String], usernames: [String]) async throws -> Conversation
    func members(room: String, adding: [String]?) async throws -> [ChatUser]
    func addAgents(room:String,agentIds:[String]) async throws -> Conversation
    func send(_ message: Outgoing) async throws -> Message
    func retryJob(_ job: AgentJob) async throws
    func addFavorite(_ message: Int64) async throws -> FavoriteItem
    func favorites(query:String,before:Int64?) async throws -> FavoritePage
    func removeFavorite(_ id:Int64) async throws
    func favoriteImage(_ favorite:Int64,image:String) async throws -> Data
    func uploadDocument(_ document:DocumentAttachment,room:String,data:Data) async throws
    func document(_ id:String,favorite:Int64?) async throws -> Data
    func uploadImage(id: String, room: String, data: Data) async throws
    func image(_ id: String) async throws -> Data
    func avatar(_ id: String) async throws -> Data
    func usage() async throws -> [ModelUsage]
    func context(room: String) async throws -> ConversationContext
    func configureContext(room: String, rounds: Int) async throws -> ConversationContext
    func compact(room: String, agent: String, requestId: String) async throws -> ContextOperation
    func clearPreview(room: String) async throws -> ClearHistoryPreview
    func clear(_ preview: ClearHistoryPreview, requestId: String) async throws -> ClearHistoryResult
    func backup(room: String) async throws -> Data
    func restore(_ bytes: Data, agent: String?, requestId: String) async throws -> Conversation
}
extension ChatAPI {
    func branch(room:String,message:Int64,name:String,requestId:String) async throws -> Conversation {throw NativeError(message:"服务端尚未支持对话分支，请升级服务端。")}
    func uploadDocument(_ document:DocumentAttachment,room:String,data:Data) async throws {throw NativeError(message:"文档接口不可用。")}
    func document(_ id:String,favorite:Int64?) async throws -> Data {throw NativeError(message:"文档接口不可用。")}
}
final class MessageAPI: ChatAPI, NotificationAPI, @unchecked Sendable {
    let base: URL
    private let token: String
    private let session: URLSession
    init(base: URL, token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.base = base; self.token = token
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    private func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                         type: String = "application/json", limit: Int = 5_000_000, timeout: TimeInterval = 15) async throws -> Data {
        var url = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query }
        var request = URLRequest(url: url.url!); request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue(type, forHTTPHeaderField: "Content-Type") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NativeError(message: "服务端没有返回有效响应。") }
        let ok = (200...299).contains(http.statusCode)
        let budget = ok ? limit : 65_536
        if response.expectedContentLength > budget { stream.task.cancel(); throw NativeError(message: "服务器响应过大。", status: http.statusCode) }
        var bytes = Data(); bytes.reserveCapacity(min(budget, 65536))
        for try await byte in stream {
            if bytes.count >= budget { stream.task.cancel(); throw NativeError(message: "服务器响应过大。", status: http.statusCode) }
            bytes.append(byte)
        }
        guard ok else {
            let fallback: String
            switch http.statusCode {
            case 401: fallback = token.hasPrefix("chat_") ? "登录已失效，请重新登录。" : "服务访问令牌未通过认证。"
            case 403: fallback = "服务器拒绝访问，请检查权限和 HTTPS 代理。"
            case 404: fallback = "服务端尚未支持此功能，请升级服务端。"
            case 413: fallback = "附件或备份超过服务允许的大小。"
            case 300...399: fallback = "服务发生重定向，请填写最终 HTTPS 地址。"
            default: fallback = "请求失败（HTTP \(http.statusCode)），请稍后重试。"
            }
            let detail = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            let message = http.statusCode == 401 || http.statusCode >= 500 ? fallback : detail?["message"] as? String ?? detail?["detail"] as? String ?? fallback
            throw NativeError(message: message, status: http.statusCode)
        }
        return bytes
    }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, query: query))
    }
    private func post<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, body: JSONSerialization.data(withJSONObject: body)))
    }
    func login(_ username: String) async throws -> LoginResult { try await post("api/conversations/account/login", ["username": username]) }
    func logout() async throws { _ = try await request("api/conversations/account/logout", body: Data("{}".utf8)) }
    func agents() async throws -> [AgentInfo] { try await get("api/agents") }
    func conversations() async throws -> [Conversation] { try await get("api/conversations") }
    func heartbeat(deviceId: String, name: String) async throws {
        _ = try await request("api/device-messages/presence", body: JSONSerialization.data(withJSONObject: ["deviceId":deviceId,"name":name,"platform":"ios"]))
    }
    func page(room: String, after: Int64? = nil, before: Int64? = nil) async throws -> MessagePage {
        var query = [URLQueryItem(name: "conversationId", value: room), URLQueryItem(name: "limit", value: "100")]
        if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get("api/device-messages", query: query)
    }
    private func identifier(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw NativeError(message: "标识无效。") }; return id
    }
    func search(query: String, room: String?, before: Int64?) async throws -> ChatSearchPage {
        var items = [URLQueryItem(name:"q",value:query)]
        if let room { items.append(URLQueryItem(name:"conversationId",value:room)) }
        if let before { items.append(URLQueryItem(name:"before",value:String(before))) }
        return try await get("api/device-messages/search",query:items)
    }
    func searchContext(room: String, message: Int64, direction: String) async throws -> ChatSearchContext {
        try await get("api/device-messages/context",query:[URLQueryItem(name:"conversationId",value:room),URLQueryItem(name:"messageId",value:String(message)),URLQueryItem(name:"direction",value:direction)])
    }
    func direct(_ agent: String) async throws -> Conversation { try await post("api/conversations/direct/\(identifier(agent))", [:]) }
    func newThread(agent: String, name: String, requestId: String) async throws -> Conversation {
        try await post("api/conversations/direct/\(identifier(agent))/threads", ["name":name,"requestId":requestId])
    }
    func branch(room:String,message:Int64,name:String,requestId:String) async throws -> Conversation {
        guard message>0 else {throw NativeError(message:"请选择已发送成功的消息。")}
        guard room.range(of:"^[A-Za-z0-9:-]{1,80}$",options:.regularExpression) != nil else {throw NativeError(message:"会话标识无效。")}
        return try JSONDecoder().decode(Conversation.self,from:await request("api/conversations/\(room)/branches",body:JSONSerialization.data(withJSONObject:["messageId":message,"name":name,"requestId":requestId]),timeout:90))
    }
    func group(name: String, agentIds: [String], usernames: [String]) async throws -> Conversation {
        try await post("api/conversations/groups", ["name":name,"agentIds":agentIds,"usernames":usernames])
    }
    func members(room: String, adding: [String]?) async throws -> [ChatUser] {
        let path = "api/conversations/\(room)/members"
        if let adding { return try await post(path, ["usernames":adding]) }; return try await get(path)
    }
    func addAgents(room:String,agentIds:[String]) async throws -> Conversation {
        try await post("api/conversations/\(room)/agents",["agentIds":agentIds])
    }
    func send(_ message: Outgoing) async throws -> Message {
        if message.quoteMessageId != nil {
            let features: [String:Bool] = try await get("api/device-messages/features")
            guard features["quotes"] == true else { throw NativeError(message:"服务端尚未支持引用回复，请先升级服务端。") }
        }
        var payload=message;payload.quote=nil;payload.documents=nil
        return try JSONDecoder().decode(Message.self, from: await request("api/device-messages", body: JSONEncoder().encode(payload)))
    }
    func addFavorite(_ message:Int64) async throws -> FavoriteItem {try await post("api/device-messages/\(message)/favorite",[:])}
    func favorites(query:String,before:Int64?) async throws -> FavoritePage {
        var items=[URLQueryItem(name:"q",value:query)]
        if let before {items.append(URLQueryItem(name:"before",value:String(before)))}
        return try await get("api/device-messages/favorites",query:items)
    }
    func removeFavorite(_ id:Int64) async throws {_ = try await request("api/device-messages/favorites/\(id)/remove",body:Data("{}".utf8))}
    func favoriteImage(_ favorite:Int64,image:String) async throws -> Data {try await request("api/device-messages/favorites/\(favorite)/images/\(identifier(image))",limit:1_048_576)}
    func retryJob(_ job: AgentJob) async throws { _ = try await request("api/device-messages/\(job.messageId)/agents/\(identifier(job.agentId))/retry", body: Data("{}".utf8)) }
    func notificationStatus() async throws -> NotificationStatus {try await get("api/device-messages/notifications/status")}
    func notifications(device:String,after:Int64?,preview:Bool) async throws -> NotificationPage {
        var query=[URLQueryItem(name:"deviceId",value:device),URLQueryItem(name:"preview",value:String(preview))]
        if let after {query.append(URLQueryItem(name:"after",value:String(after)))}
        return try await get("api/device-messages/notifications",query:query)
    }
    func registerNotifications(_ registration:PushRegistration) async throws {_ = try await request("api/device-messages/notifications/devices",body:JSONEncoder().encode(registration))}
    func removeNotifications(device:String) async throws {_ = try await request("api/device-messages/notifications/devices/\(identifier(device))/remove",body:Data("{}".utf8))}
    func uploadDocument(_ document:DocumentAttachment,room:String,data:Data) async throws {
        guard data.count<=10*1024*1024 else {throw NativeError(message:"文件不能超过 10 MB。")}
        _ = try await request("api/device-messages/documents",query:[URLQueryItem(name:"id",value:try identifier(document.id)),URLQueryItem(name:"conversationId",value:room),URLQueryItem(name:"name",value:document.name)],body:data,type:"application/octet-stream",timeout:90)
    }
    func document(_ id:String,favorite:Int64?) async throws -> Data {
        let prefix=favorite.map {"api/device-messages/favorites/\($0)/documents/"} ?? "api/device-messages/documents/"
        return try await request(prefix+identifier(id),limit:10*1024*1024,timeout:60)
    }
    func uploadImage(id: String, room: String, data: Data) async throws {
        guard data.count <= 1_048_576 else { throw NativeError(message: "图片不能超过 1 MB。") }
        _ = try await request("api/device-messages/images", query: [URLQueryItem(name:"id",value:try identifier(id)), URLQueryItem(name:"conversationId",value:room)], body:data,type:"image/jpeg")
    }
    func image(_ id: String) async throws -> Data { try await request("api/device-messages/images/\(identifier(id))", limit:1_048_576) }
    func avatar(_ id: String) async throws -> Data {
        guard id.range(of:"^[a-z0-9-]{1,80}$",options:.regularExpression) != nil else { throw NativeError(message:"头像标识无效。") }
        return try await request("api/agent-avatars/\(id)",limit:2_097_152)
    }
    func usage() async throws -> [ModelUsage] { try await get("api/agents/usage") }
    func context(room: String) async throws -> ConversationContext { try await get("api/conversations/context",query:[URLQueryItem(name:"conversationId",value:room)]) }
    func configureContext(room: String, rounds: Int) async throws -> ConversationContext { try await post("api/conversations/context/settings",["conversationId":room,"recentRounds":rounds]) }
    func compact(room: String, agent: String, requestId: String) async throws -> ContextOperation { try await post("api/conversations/context/compact",["conversationId":room,"agentId":agent,"requestId":requestId]) }
    func clearPreview(room: String) async throws -> ClearHistoryPreview { try await get("api/conversations/context/clear-preview",query:[URLQueryItem(name:"conversationId",value:room)]) }
    func clear(_ preview: ClearHistoryPreview, requestId: String) async throws -> ClearHistoryResult {
        try await post("api/conversations/context/clear",["conversationId":preview.conversationId,"requestId":requestId,"expectedLatestMessageId":preview.latestMessageId,"expectedHistoryRevision":preview.historyRevision,"confirm":true])
    }
    func backup(room: String) async throws -> Data { try await request("api/conversations/backups",query:[URLQueryItem(name:"conversationId",value:room)],limit:32*1024*1024,timeout:60) }
    func restore(_ bytes: Data, agent: String?, requestId: String) async throws -> Conversation {
        guard !bytes.isEmpty, bytes.count <= 32*1024*1024 else { throw NativeError(message:"备份不能超过 32 MB。") }
        var query = [URLQueryItem(name:"requestId",value:requestId)]
        if let agent { query.append(URLQueryItem(name:"agentId",value:agent)) }
        return try JSONDecoder().decode(Conversation.self, from: await request("api/conversations/backups",query:query,body:bytes,type:"application/zip",timeout:60))
    }
}

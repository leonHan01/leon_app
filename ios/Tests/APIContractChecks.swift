import Foundation

// Intercepts URLSession itself; no production server or model request is made.
final class ContractTransport: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responder: ((URLRequest) throws -> (Int,Data))?
    static func install(_ value: @escaping (URLRequest) throws -> (Int,Data)) {
        lock.lock();defer {lock.unlock()};responder = value
    }
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        Self.lock.lock();let handler = Self.responder;Self.lock.unlock()
        do {
            guard let handler else {throw NativeError(message:"Missing HTTP fixture")}
            let (status,bytes) = try handler(request)
            let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Length":String(bytes.count)])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:bytes);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}

private func jsonBody(_ request: URLRequest) throws -> [String:Any] {
    try JSONSerialization.jsonObject(with:rawBody(request)) as? [String:Any] ?? [:]
}
private func rawBody(_ request:URLRequest) throws -> Data {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let input = request.httpBodyStream {
        input.open();defer {input.close()};var bytes = [UInt8](repeating:0,count:4096)
        while input.hasBytesAvailable {
            let count = input.read(&bytes,maxLength:bytes.count)
            guard count >= 0 else {throw NativeError(message:"Request stream failed")}
            if count == 0 {break};data.append(contentsOf:bytes.prefix(count))
        }
    }
    return data
}
private func requireHTTP(_ value: Bool,_ message: String) throws {
    if !value {throw NativeError(message:"HTTP contract: "+message)}
}
@MainActor
extension Checks {
    func checkHTTPContracts() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [ContractTransport.self]
        let api = MessageAPI(base:URL(string:"https://contract.invalid")!,token:"chat_fixture",configuration:config)
        try await run("URLSession account, paging, message and presence contracts") {
            ContractTransport.install { request in
                try requireHTTP(request.value(forHTTPHeaderField:"Authorization") == "Bearer chat_fixture","authorization")
                let url = request.url!,components = URLComponents(url:url,resolvingAgainstBaseURL:false)!
                let query = Dictionary(uniqueKeysWithValues:(components.queryItems ?? []).map {($0.name,$0.value ?? "")})
                switch url.path {
                case "/api/conversations/account/login":
                    try requireHTTP(try jsonBody(request)["username"] as? String == "Alice","username payload")
                    return (200,Data(#"{"user":{"id":"user-1","username":"Alice"},"sessionToken":"chat_fixture"}"#.utf8))
                case "/api/device-messages" where request.httpMethod == "GET":
                    try requireHTTP(query["conversationId"] == "home:user-1" && query["after"] == "12" && query["limit"] == "100","paging and room encoding")
                    return (200,Data(#"{"messages":[],"hasMore":false,"jobs":[],"contextOperations":[],"historyRevision":3}"#.utf8))
                case "/api/device-messages":
                    let body = try jsonBody(request)
                    try requireHTTP(body["platform"] as? String == "ios" && body["text"] as? String == "你好" && body["conversationId"] as? String == "home:user-1","message payload")
                    return (200,Data(#"{"id":13,"clientMessageId":"fixture-message","deviceId":"fixture-device","sender":"Alice","platform":"ios","text":"你好","createdAt":1000,"conversationId":"home:user-1","role":"user","images":[],"userId":"user-1"}"#.utf8))
                case "/api/device-messages/presence":
                    try requireHTTP(try jsonBody(request)["platform"] as? String == "ios","presence platform")
                    return (200,Data("{}".utf8))
                default:throw NativeError(message:"Unexpected fixture URL: "+url.path)
                }
            }
            try expect(try await api.login("Alice").user.home == "home:user-1","login decoding")
            try expect(try await api.page(room:"home:user-1",after:12,before:nil).historyRevision == 3,"history revision decoding")
            let message = Outgoing(clientMessageId:"fixture-message",deviceId:"fixture-device",sender:"Alice",platform:"ios",text:"你好",conversationId:"home:user-1")
            try expect(try await api.send(message).id == 13,"message decoding")
            try await api.heartbeat(deviceId:"fixture-device",name:"Alice")
        }
        try await run("URLSession clear safeguards, ZIP restore and expired session contracts") {
            ContractTransport.install { request in
                let path = request.url!.path
                switch path {
                case "/api/conversations/context/clear":
                    let body = try jsonBody(request)
                    try requireHTTP(body["expectedLatestMessageId"] as? Int == 12 && body["expectedHistoryRevision"] as? Int == 3 && body["confirm"] as? Bool == true && body["requestId"] as? String == "same-request","clear concurrency safeguards")
                    return (200,Data(#"{"clearedMessages":12,"historyRevision":4}"#.utf8))
                case "/api/conversations/backups":
                    try requireHTTP(request.httpMethod == "POST" && request.value(forHTTPHeaderField:"Content-Type") == "application/zip","ZIP restore content type")
                    let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
                    try requireHTTP(query.contains(URLQueryItem(name:"requestId",value:"stable-restore")) && query.contains(URLQueryItem(name:"agentId",value:"agent-target")),"restore idempotency and target")
                    return (200,Data(#"{"id":"thread:fixture","name":"恢复的对话","kind":"direct","agentId":"agent-target","agentIds":["agent-target"],"ownerId":"user-1"}"#.utf8))
                default:return (401,Data(#"{"message":"internal secret must not surface"}"#.utf8))
                }
            }
            let preview = ClearHistoryPreview(conversationId:"home:user-1",conversationName:"Home",messageCount:12,latestMessageId:12,historyRevision:3,hasActiveWork:false)
            try expect(try await api.clear(preview,requestId:"same-request").historyRevision == 4,"clear response")
            try expect(try await api.restore(Data([0x50,0x4b]),agent:"agent-target",requestId:"stable-restore").id == "thread:fixture","restore response")
            do {_ = try await api.usage();throw NativeError(message:"401 was accepted")}
            catch let failure as NativeError {try expect(failure.expired && !failure.message.contains("internal secret"),"401 classification or information leak")}
        }
        try await checkAndroidFeatureContracts(api)
    }
    private func checkAndroidFeatureContracts(_ api:MessageAPI) async throws {
        let agent = "11111111-1111-4111-8111-111111111111"
        let group = #"{"id":"group:contract","name":"项目群","kind":"group","agentId":null,"agentIds":["11111111-1111-4111-8111-111111111111"],"ownerId":""}"#
        let direct = #"{"id":"thread:contract","name":"新对话","kind":"direct","agentId":"11111111-1111-4111-8111-111111111111","agentIds":["11111111-1111-4111-8111-111111111111"],"ownerId":"user-1"}"#
        try await run("Android Agent directory, private chat, named thread and group contracts") {
            ContractTransport.install {request in
                let path = request.url!.path
                switch path {
                case "/api/agents":return (200,Data(#"[{"id":"11111111-1111-4111-8111-111111111111","name":"写作","handle":"writer","provider":"openai","model":"gpt-4o","enabled":true,"avatarId":"alfred","description":"写作助手"}]"#.utf8))
                case "/api/conversations":return (200,Data(("["+group+"]").utf8))
                case "/api/conversations/direct/\(agent)":try requireHTTP(request.httpMethod == "POST","private chat method");return (200,Data(direct.utf8))
                case "/api/conversations/direct/\(agent)/threads":
                    let body = try jsonBody(request)
                    try requireHTTP(body["name"] as? String == "新对话" && body["requestId"] as? String == "stable-thread","named thread payload")
                    return (200,Data(direct.utf8))
                case "/api/conversations/groups":
                    let body = try jsonBody(request)
                    try requireHTTP(body["name"] as? String == "项目群" && body["agentIds"] as? [String] == [agent] && body["usernames"] as? [String] == ["Bob"],"group Agent and user selection")
                    return (200,Data(group.utf8))
                default:throw NativeError(message:"Unexpected directory URL: "+path)
                }
            }
            try expect(try await api.agents().first?.description == "写作助手","Agent intro unavailable")
            try expect(try await api.conversations().first?.ownerId == "","legacy group decoding")
            try expect(try await api.direct(agent).direct,"private chat not decoded")
            try expect(try await api.newThread(agent:agent,name:"新对话",requestId:"stable-thread").id == "thread:contract","named thread not decoded")
            try expect(try await api.group(name:"项目群",agentIds:[agent],usernames:["Bob"]).name == "项目群","group creation decoding")
        }
        try await run("Android group members and invitations preserve colon-containing room IDs") {
            ContractTransport.install {request in
                try requireHTTP(request.url!.path == "/api/conversations/group:contract/members","room path was double encoded")
                if request.httpMethod == "POST" {try requireHTTP(try jsonBody(request)["usernames"] as? [String] == ["Bob"],"group invitation payload")}
                return (200,Data(#"[{"id":"user-2","username":"Bob"}]"#.utf8))
            }
            try expect(try await api.members(room:"group:contract",adding:nil).first?.username == "Bob","member list decoding")
            try expect(try await api.members(room:"group:contract",adding:["Bob"]).count == 1,"member invitation decoding")
        }
        try await run("Group Agent invitations use additive authenticated room endpoint") {
            ContractTransport.install {request in
                try requireHTTP(request.httpMethod == "POST" && request.url!.path == "/api/conversations/group:contract/agents","Agent invitation method or room path")
                try requireHTTP(request.value(forHTTPHeaderField:"Authorization") == "Bearer chat_fixture","Agent invitation authentication")
                try requireHTTP(try jsonBody(request)["agentIds"] as? [String] == [agent],"Agent invitation payload")
                return (200,Data(group.utf8))
            }
            let updated = try await api.addAgents(room:"group:contract",agentIds:[agent])
            try expect(updated.id == "group:contract" && updated.agentIds == [agent],"updated group membership decoding")
        }
        try await run("Android context rounds, manual compression and clear preview contracts") {
            let context = #"{"conversationId":"group:contract","recentRounds":20,"inputTokenBudget":32000,"topicStartedAfter":12,"agents":[{"agentId":"11111111-1111-4111-8111-111111111111","agentName":"写作","summary":"摘要","lastCompressedAt":1000,"estimatedInputTokens":123,"retainedRounds":2,"phase":"IDLE"}]}"#
            ContractTransport.install {request in
                let path = request.url!.path
                switch path {
                case "/api/conversations/context":
                    try requireHTTP(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.contains(URLQueryItem(name:"conversationId",value:"group:contract")),"context room query")
                    return (200,Data(context.utf8))
                case "/api/conversations/context/settings":
                    let body = try jsonBody(request)
                    try requireHTTP(body["recentRounds"] as? Int == 20 && body["conversationId"] as? String == "group:contract","retained rounds payload")
                    return (200,Data(context.utf8))
                case "/api/conversations/context/compact":
                    let body = try jsonBody(request)
                    try requireHTTP(body["agentId"] as? String == agent && body["requestId"] as? String == "stable-compact" && body["conversationId"] as? String == "group:contract","compression target and idempotency")
                    return (200,Data(#"{"id":"operation","agentId":"11111111-1111-4111-8111-111111111111","agentName":"写作","status":"PENDING","error":"","result":"","createdAt":1000,"kind":"COMPACT"}"#.utf8))
                case "/api/conversations/context/clear-preview":return (200,Data(#"{"conversationId":"group:contract","conversationName":"项目群","messageCount":12,"latestMessageId":12,"historyRevision":3,"hasActiveWork":true}"#.utf8))
                default:throw NativeError(message:"Unexpected context URL: "+path)
                }
            }
            try expect(try await api.context(room:"group:contract").agents.first?.summary == "摘要","context summary decoding")
            try expect(try await api.configureContext(room:"group:contract",rounds:20).recentRounds == 20,"round selection decoding")
            try expect(try await api.compact(room:"group:contract",agent:agent,requestId:"stable-compact").status == "PENDING","manual compression decoding")
            try expect(try await api.clearPreview(room:"group:contract").hasActiveWork,"clear busy safeguard decoding")
        }
        try await run("Android image attachments, failed reply retry, history and backup download contracts") {
            let image = "22222222-2222-4222-8222-222222222222",jpeg = Data([0xff,0xd8,0xff,0xd9]),zip = Data("PK fixture".utf8)
            ContractTransport.install {request in
                let url = request.url!,path = url.path
                try requireHTTP(request.value(forHTTPHeaderField:"Authorization") == "Bearer chat_fixture","authenticated media")
                switch path {
                case "/api/device-messages/images":
                    try requireHTTP(request.value(forHTTPHeaderField:"Content-Type") == "image/jpeg" && rawBody(request) == jpeg,"raw JPEG upload")
                    let query = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!
                    try requireHTTP(query.contains(URLQueryItem(name:"id",value:image)) && query.contains(URLQueryItem(name:"conversationId",value:"group:contract")),"attachment origin")
                    return (200,Data("{}".utf8))
                case "/api/device-messages/images/\(image)","/api/agent-avatars/alfred":return (200,jpeg)
                case "/api/device-messages/12/agents/\(agent)/retry":try requireHTTP(request.httpMethod == "POST","failed reply retry method");return (200,Data("{}".utf8))
                case "/api/device-messages":
                    try requireHTTP(URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.contains(URLQueryItem(name:"before",value:"12")),"older history cursor")
                    return (200,Data(#"{"messages":[],"hasMore":false,"historyRevision":3}"#.utf8))
                case "/api/conversations/backups":try requireHTTP(request.httpMethod == "GET","backup export method");return (200,zip)
                default:throw NativeError(message:"Unexpected media URL: "+path)
                }
            }
            try await api.uploadImage(id:image,room:"group:contract",data:jpeg)
            try expect(try await api.image(image) == jpeg,"attachment download")
            try expect(try await api.avatar("alfred") == jpeg,"avatar download")
            try await api.retryJob(AgentJob(messageId:12,agentId:agent,agentName:"写作",status:"FAILED",error:"offline"))
            try expect(try await api.page(room:"group:contract",after:nil,before:12).historyRevision == 3,"older history decoding")
            try expect(try await api.backup(room:"group:contract") == zip,"full backup download")
        }
    }
}

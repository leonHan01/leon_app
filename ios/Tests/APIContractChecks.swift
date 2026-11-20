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
    var data = request.httpBody ?? Data()
    if data.isEmpty, let input = request.httpBodyStream {
        input.open();defer {input.close()};var bytes = [UInt8](repeating:0,count:4096)
        while input.hasBytesAvailable {
            let count = input.read(&bytes,maxLength:bytes.count)
            guard count >= 0 else {throw NativeError(message:"Request stream failed")}
            if count == 0 {break};data.append(contentsOf:bytes.prefix(count))
        }
    }
    return try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
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
    }
}

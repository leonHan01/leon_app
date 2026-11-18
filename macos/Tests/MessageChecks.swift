import Foundation

// Standalone checks compile the real network/model source and also run with Command Line
// Tools alone, without requiring the XCTest framework from a full Xcode installation.
@main
struct MessageChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ClientError.message(message) }
    }
    static func main() async throws {
        try endpointChecks()
        try decodingChecks()
        try mentionChecks()
        try check(HTTPFailure.message(for: 401)?.contains("令牌") == true, "401 must explain authentication failure")
        try check(HTTPFailure.message(for: 403)?.contains("令牌") == false, "Proxy 403 must not blame the token")
        try check(HTTPFailure.message(for: 403)?.contains("代理") == true, "403 must explain server permissions/proxy")
        try check(HTTPFailure.message(for: 502)?.contains("运行状态") == true, "502 must explain service failure")
        print("PASS: authentication, proxy denial and upstream failures stay distinct")
        print("PASS: endpoint validation and Unicode/Unix-millisecond protocol decoding")
        print("PASS: @ mention caret replacement, Unicode names, email boundaries and selections")
        if let address = ProcessInfo.processInfo.environment["LEONAPP_TEST_SERVER"],
           let token = ProcessInfo.processInfo.environment["LEONAPP_TEST_TOKEN"] {
            try await networkChecks(address, token)
            print("PASS: real HTTP send, idempotent retry, incremental receive and second-device reply")
            if let agentId = ProcessInfo.processInfo.environment["LEONAPP_TEST_AGENT"] {
                try await agentChecks(address, token, agentId)
                print("PASS: Agent directory, private conversation isolation, group creation and mention job protocol")
            }
        } else { print("SKIP: isolated HTTP checks (set LEONAPP_TEST_SERVER and LEONAPP_TEST_TOKEN)") }
    }
    static func endpointChecks() throws {
        let remote = try Endpoint.normalize(" https://121.40.254.112/ ")
        try check(remote.absoluteString == "https://121.40.254.112", "HTTPS normalization failed")
        let loopback = try Endpoint.normalize("http://127.0.0.1:8080")
        try check(loopback.absoluteString == "http://127.0.0.1:8080", "Loopback normalization failed")
        for value in ["http://example.com", "https://token@example.com", "https://example.com?token=x", "https://example.com/api", "https://example.com#x", "ftp://example.com", "https://example.com:99999"] {
            var rejected = false
            do { _ = try Endpoint.normalize(value) } catch { rejected = true }
            try check(rejected, "Accepted unsafe endpoint: \(value)")
        }
    }
    static func decodingChecks() throws {
        let data = Data(#"{"messages":[{"id":1,"clientMessageId":"client","deviceId":"device","sender":"手机","platform":"android","text":"你好 🚀\n第二行","createdAt":1700000000123}],"hasMore":false}"#.utf8)
        let page = try JSONDecoder().decode(MessagePage.self, from: data)
        try check(page.messages[0].text == "你好 🚀\n第二行", "Unicode/newline decoding failed")
        try check(abs(page.messages[0].date.timeIntervalSince1970 - 1700000000.123) < 0.001, "Millisecond date decoding failed")
    }
    static func mentionChecks() throws {
        let bare = MentionCompletion.token(in: "你好 @", selection: NSRange(location: 4, length: 0))
        try check(bare?.query == "", "Bare @ did not open candidates")
        try check(MentionCompletion.matches(name: "写作助手", handle: "writer", query: "写作"), "Chinese name did not match")
        try check(MentionCompletion.matches(name: "写作助手", handle: "writer", query: "WRI"), "Handle filtering is not case insensitive")
        guard let adjacent = MentionCompletion.token(in: "你好@写", selection: NSRange(location: 4, length: 0)) else { throw ClientError.message("@ after Chinese text did not match") }
        try check(MentionCompletion.replacing(adjacent, in: "你好@写", with: "writer").text == "你好 @writer ", "Mention after Chinese text missed the routing delimiter")
        for text in ["me@example.com", "@writer ", "@a."] {
            try check(MentionCompletion.token(in: text, selection: NSRange(location: (text as NSString).length, length: 0)) == nil, "Unexpected mention candidate for \(text)")
        }
        try check(MentionCompletion.token(in: "@w", selection: NSRange(location: 0, length: 2)) == nil, "Selected text must not trigger candidates")
        guard let token = MentionCompletion.token(in: "😀 @wriXYZ 保留", selection: NSRange(location: 7, length: 0)) else { throw ClientError.message("Caret token missing") }
        try check(token.query == "wri", "Wrong caret query")
        let result = MentionCompletion.replacing(token, in: "😀 @wriXYZ 保留", with: "writer")
        try check(result.text == "😀 @writer 保留" && result.caret == 11, "Replacement lost text or moved caret incorrectly")
        try check(MentionCompletion.token(in: result.text, selection: NSRange(location: result.caret, length: 0)) == nil, "Selected mention reopened candidates")
    }
    static func networkChecks(_ address: String, _ token: String) async throws {
        let api = MessageAPI(base: try Endpoint.normalize(address), token: token)
        let before = try await api.page()
        let cursor = before.messages.last?.id ?? 0
        let outgoing = Outgoing(clientMessageId: UUID().uuidString.lowercased(), deviceId: UUID().uuidString.lowercased(), sender: "Mac 集成测试", platform: "macos", text: "来自 Mac 的真实请求 🚀\n第二行")
        try await api.heartbeat(deviceId: outgoing.deviceId, name: outgoing.sender)
        let sent = try await api.send(outgoing)
        try check(sent.text == outgoing.text, "HTTP send changed text")
        let retried = try await api.send(outgoing)
        try check(sent.id == retried.id, "Retry duplicated the message")
        let received = try await api.page(after: cursor)
        try check(received.messages.filter { $0.id == sent.id }.count == 1, "Incremental receive lost/duplicated the message")
        let android = Outgoing(clientMessageId: UUID().uuidString.lowercased(), deviceId: UUID().uuidString.lowercased(), sender: "Android 集成测试", platform: "android", text: "收到 Mac，来自 Android 的回复")
        _ = try await api.send(android)
        let response = try await api.page(after: sent.id)
        try check(response.messages.last?.text == android.text, "Second-device reply not received")
    }
    static func agentChecks(_ address: String, _ token: String, _ agentId: String) async throws {
        let api = MessageAPI(base: try Endpoint.normalize(address), token: token)
        let agents = try await api.agents()
        try check(agents.contains { $0.id == agentId }, "Configured Agent not listed")
        let avatarId = agents.first { $0.id == agentId }?.avatarId ?? "alfred"
        let avatar = try await api.avatarData(avatarId)
        try check(avatar.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "Authenticated avatar did not return PNG data")
        let cachedAvatar = try await api.avatarData(avatarId)
        try check(avatar == cachedAvatar, "Cached avatar data changed")
        let direct = try await api.direct(agentId)
        let group = try await api.group(name: "Mac 协议测试群", agentIds: [agentId])
        let rooms = try await api.conversations()
        try check(rooms.contains { $0.id == direct.id } && rooms.contains { $0.id == group.id }, "Conversation directory incomplete")
        let outgoing = Outgoing(clientMessageId: UUID().uuidString.lowercased(), deviceId: UUID().uuidString.lowercased(), sender: "Mac", platform: "macos", text: "独立私聊问题", conversationId: direct.id, mentionAgentIds: [])
        let sent = try await api.send(outgoing)
        let privatePage = try await api.page(conversation: direct.id)
        try check(privatePage.messages.contains { $0.id == sent.id }, "Private message not in private history")
        let shared = try await api.page()
        try check(!shared.messages.contains { $0.id == sent.id }, "Private message leaked into shared history")
        let mention = Outgoing(clientMessageId: UUID().uuidString.lowercased(), deviceId: UUID().uuidString.lowercased(), sender: "Mac", platform: "macos", text: "请回答", conversationId: group.id, mentionAgentIds: [agentId])
        let groupMessage = try await api.send(mention)
        let groupPage = try await api.page(conversation: group.id)
        try check(groupPage.jobs?.contains { $0.messageId == groupMessage.id && $0.agentId == agentId } == true, "Mention did not create the targeted reply job")
    }
}

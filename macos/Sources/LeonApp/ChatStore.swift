import SwiftUI
import CryptoKit

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [Message] = []
    @Published var pending: [Outgoing] = []
    @Published var draft = ""
    @Published var agents: [AgentInfo] = []
    @Published var conversations: [Conversation] = []
    @Published var jobs: [AgentJob] = []
    @Published var selectedConversationId = "shared"
    @Published var showNewGroup = false
    @Published private(set) var avatarSessionKey = UUID().uuidString
    func avatarId(for agentId: String?) -> String { agents.first { $0.id == agentId }?.avatarId ?? "alfred" }
    func avatarData(_ id: String) async -> Data? { guard let api else { return nil }; return try? await api.avatarData(id) }
    private var connectionId = UUID()
    private var drafts: [String:String] = [:]
    var currentPending: [Outgoing] { pending.filter { ($0.conversationId ?? "shared") == selectedConversationId } }
    var selectedConversation: Conversation? { conversations.first { $0.id == selectedConversationId } }
    var title: String { selectedConversation?.name ?? "设备群聊" }
    var availableAgents: [AgentInfo] { agents.filter { $0.enabled && (selectedConversation?.agentIds.contains($0.id) ?? (selectedConversationId == "shared")) } }

    func selectConversation(_ id: String) {
        guard id != selectedConversationId else { return }
        drafts[selectedConversationId] = draft
        selectedConversationId = id
        draft = drafts[id] ?? ""
        generation = UUID(); messages = []; jobs = []; initialLoaded = false; hasOlder = false; loadingOlder = false
        beginPolling()
    }
    func mention(_ agent: AgentInfo) { draft += (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + "@\(agent.handle) " }
    func openDirect(_ agent: AgentInfo) async {
        guard let api else { return }
        let connection = connectionId
        do {
            let room = try await api.direct(agent.id); let rooms = try await api.conversations()
            guard connection == connectionId else { return }
            conversations = rooms; selectConversation(room.id)
        }
        catch { self.error = friendly(error) }
    }
    func createGroup(name: String, agentIds: [String]) async {
        guard let api else { return }
        let connection = connectionId
        do {
            let room = try await api.group(name: name, agentIds: agentIds); let rooms = try await api.conversations()
            guard connection == connectionId else { return }
            conversations = rooms; showNewGroup = false; selectConversation(room.id)
        }
        catch { self.error = friendly(error) }
    }
    func retryJob(_ job: AgentJob) async {
        guard let api else { return }
        do { try await api.retryJob(job); beginPolling() } catch { self.error = friendly(error) }
    }
    @Published var status = "尚未连接"
    @Published var error: String?
    @Published var connected = false
    @Published var hasOlder = false
    @Published var loadingOlder = false
    @Published var sending = Set<String>()
    @Published var configuring = false
    @Published var showSettings = false
    @Published var address = UserDefaults.standard.string(forKey: "server") ?? "https://121.40.254.112"
    @Published var sender = UserDefaults.standard.string(forKey: "sender") ?? Host.current().localizedName ?? "我的 Mac"
    let deviceId: String
    private var api: MessageAPI?
    private var poller: Task<Void, Never>?
    private var generation = UUID()
    private var pendingKey = ""
    private var active = true
    private var initialLoaded = false
    var hasConnection: Bool { api != nil }

    init() {
        deviceId = UserDefaults.standard.string(forKey: "deviceId") ?? UUID().uuidString.lowercased()
        UserDefaults.standard.set(deviceId, forKey: "deviceId")
    }

    func start() async {
        guard api == nil else { return }
        let token = Keychain.read()
        guard !token.isEmpty else { showSettings = true; return }
        do {
            let base = try Endpoint.normalize(address)
            api = MessageAPI(base: base, token: token)
            restorePending(base: base, token: token)
            status = "正在连接…"
            beginPolling()
        } catch { self.error = friendly(error); showSettings = true }
    }

    func configure(address: String, token: String, sender: String) async {
        guard !configuring else { return }
        configuring = true
        defer { configuring = false }
        do {
            let base = try Endpoint.normalize(address)
            let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = sender.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty, secret.utf8.count <= 900, !secret.contains(where: { $0.isWhitespace }),
                  !secret.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !name.isEmpty, name.utf16.count <= 60, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ClientError.message("请填写访问令牌和 1–60 字的设备名称。")
            }
            guard sending.isEmpty else { throw ClientError.message("请等待正在发送的消息完成，再切换连接。") }
            let candidate = MessageAPI(base: base, token: secret)
            let page = try await candidate.page()
            let directory = try await candidate.agents()
            let rooms = try await candidate.conversations()
            try Keychain.save(secret)
            generation = UUID(); connectionId = UUID(); avatarSessionKey = UUID().uuidString
            selectedConversationId = "shared"; drafts = [:]
            agents = directory; conversations = rooms; jobs = page.jobs ?? []
            poller?.cancel()
            api = candidate
            self.address = base.absoluteString
            self.sender = name
            UserDefaults.standard.set(self.address, forKey: "server")
            UserDefaults.standard.set(name, forKey: "sender")
            restorePending(base: base, token: secret)
            messages = page.messages
            initialLoaded = true
            hasOlder = page.hasMore
            reconcilePending()
            draft = ""
            connected = true
            status = "已连接 · 自动同步"
            error = nil
            showSettings = false
            beginPolling()
        } catch { self.error = friendly(error) }
    }

    func setActive(_ value: Bool) {
        active = value
        if value { beginPolling() } else { poller?.cancel(); status = "已暂停 · 返回后自动同步"; connected = false }
    }

    func reconnect() { beginPolling() }

    private func beginPolling() {
        poller?.cancel()
        guard active, let api else { return }
        let current = generation
        poller = Task { [weak self] in
            var delay: UInt64 = 2
            var cycle = 0
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                do {
                    if cycle % 5 == 0 {
                        let agents = try await api.agents()
                        let rooms = try await api.conversations()
                        guard !Task.isCancelled, self.generation == current else { return }
                        self.agents = agents; self.conversations = rooms
                    }
                    cycle += 1
                    let initial = !self.initialLoaded
                    let page = try await api.page(conversation: self.selectedConversationId, after: initial ? nil : self.messages.last?.id ?? 0)
                    guard !Task.isCancelled, self.generation == current else { return }
                    if initial { self.hasOlder = page.hasMore; self.initialLoaded = true }
                    self.jobs = page.jobs ?? []
                    self.merge(page.messages)
                    self.connected = true
                    self.status = "已连接 · 自动同步"
                    delay = 2
                    if !initial && page.hasMore { continue }
                } catch {
                    guard !Task.isCancelled, self.generation == current else { return }
                    self.connected = false
                    self.status = self.friendly(error)
                    delay = min(delay * 2, 30)
                }
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            }
        }
    }

    func loadOlder() async {
        guard let api, let first = messages.first, hasOlder, !loadingOlder else { return }
        let current = generation
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await api.page(conversation: selectedConversationId, before: first.id)
            guard current == generation else { return }
            merge(page.messages)
            hasOlder = page.hasMore
        } catch { if current == generation { self.error = friendly(error) } }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard api != nil, !configuring, !text.isEmpty, text.utf16.count <= 8000 else { return }
        let message = Outgoing(clientMessageId: UUID().uuidString.lowercased(), deviceId: deviceId, sender: sender, platform: "macos", text: text, conversationId: selectedConversationId, mentionAgentIds: [])
        pending.append(message)
        savePending()
        draft = ""
        await retry(message)
    }

    func retry(_ message: Outgoing) async {
        guard let api, !configuring, !sending.contains(message.id) else { return }
        let current = connectionId
        sending.insert(message.id)
        defer { sending.remove(message.id) }
        do {
            // Sending must not advance the receive cursor: fetch all intervening messages first.
            _ = try await api.send(message)
            guard current == connectionId else { return }
            pending.removeAll { $0.id == message.id }
            savePending()
            beginPolling()
        } catch { if current == connectionId { self.error = friendly(error) } }
    }

    private func merge(_ incoming: [Message]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in incoming { byId[message.id] = message }
        messages = byId.values.sorted { $0.id < $1.id }
        reconcilePending()
    }
    private func reconcilePending() {
        let confirmed = Set(messages.filter { $0.deviceId == deviceId }.map(\.clientMessageId))
        pending.removeAll { confirmed.contains($0.clientMessageId) }
        savePending()
    }
    private func restorePending(base: URL, token: String) {
        pendingKey = "outbox." + SHA256.hash(data: Data((base.absoluteString + "\n" + token).utf8)).map { String(format: "%02x", $0) }.joined()
        pending = UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode([Outgoing].self, from: $0) } ?? []
    }
    private func savePending() { UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: pendingKey) }
    private func friendly(_ error: Error) -> String {
        if error is ClientError { return error.localizedDescription }
        if let e = error as? URLError, e.code == .cancelled { return "请求已取消" }
        return "连接未完成，请检查服务地址、网络及 HTTPS 证书后重试。"
    }
}

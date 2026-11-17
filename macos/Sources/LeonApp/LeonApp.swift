import SwiftUI
import AppKit

@main
struct LeonApp: App {
    @StateObject private var store = ChatStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        Window("Leon", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 560)
                .task { await store.start() }
                .onChange(of: phase) { store.setActive($0 == .active) }
        }
        .defaultSize(width: 1060, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("连接设置…") { store.showSettings = true }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button("立即同步") { store.reconnect() }.keyboardShortcut("r")
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: ChatStore
    private let accent = Color(red: 0.18, green: 0.36, blue: 0.89)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundStyle(accent)
                    Text("Leon").font(.system(size: 25, weight: .bold, design: .rounded))
                }.padding(.top, 28)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("会话").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.showNewGroup = true } label: { Image(systemName: "plus.bubble") }
                                .buttonStyle(.borderless).disabled(!store.hasConnection).help("新建群聊")
                        }
                        if store.conversations.isEmpty { Text("连接后显示会话").font(.caption).foregroundStyle(.secondary) }
                        ForEach(store.conversations) { room in
                            Button { store.selectConversation(room.id) } label: {
                                HStack(spacing: 8) {
                                    if room.kind == "direct" { AgentAvatarView(store: store, avatarId: store.avatarId(for: room.agentId), size: 28) }
                                    else { Image(systemName: "number").frame(width: 28) }
                                    Text(room.name).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(store.selectedConversationId == room.id ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                        Text("AGENTS · 私聊").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 18)
                        ForEach(store.agents.filter { $0.enabled }) { agent in
                            Button { Task { await store.openDirect(agent) } } label: {
                                HStack(spacing: 9) {
                                    AgentAvatarView(store: store, avatarId: agent.avatarId ?? "alfred")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(agent.name).lineLimit(1)
                                        Text("@\(agent.handle) · \(agent.provider)").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 7)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text("私聊直接回复\n群聊中 @指定 Agent").font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                Divider()
                Button { store.showSettings = true } label: {
                    Label("连接设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(.bottom, 18)
            }.padding(.horizontal, 20).frame(width: 208).frame(maxHeight: .infinity).background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    if store.selectedConversation?.kind == "direct" {
                        AgentAvatarView(store: store, avatarId: store.avatarId(for: store.selectedConversation?.agentId), size: 42)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.title).font(.system(size: 19, weight: .semibold))
                        HStack(spacing: 6) {
                            Circle().fill(store.connected ? .green : .orange).frame(width: 6, height: 6)
                            Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    Button { store.reconnect() } label: { Image(systemName: "arrow.clockwise") }.help("立即同步")
                    Button { store.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("连接设置")
                }.buttonStyle(.borderless).padding(.horizontal, 26).padding(.vertical, 24)
                Divider()
                timeline
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if store.selectedConversation?.kind != "direct" {
                        HStack {
                            Menu("@ Agent") {
                                ForEach(store.availableAgents) { agent in Button("\(agent.name)  @\(agent.handle)") { store.mention(agent) } }
                            }.disabled(store.availableAgents.isEmpty)
                            Text("只有被 @ 的 Agent 会回复").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else { Text("私聊 · Agent 将直接回复").font(.caption).foregroundStyle(.secondary) }
                    MentionComposer(store: store)
                    HStack {
                        Text("⌘ ↵ 发送 · 文字最多 8,000 字符").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if store.draft.utf16.count > 8000 { Text("已超出字数限制").font(.caption).foregroundStyle(.red) }
                        Button { Task { await store.sendDraft() } } label: {
                            Label("发送", systemImage: "arrow.up").padding(.horizontal, 10)
                        }.buttonStyle(.borderedProminent).tint(accent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(store.configuring || !store.hasConnection || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.draft.utf16.count > 8000)
                    }
                }.padding(20)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $store.showSettings) { ConnectionView(store: store) }
        .sheet(isPresented: $store.showNewGroup) { NewGroupView(store: store) }
        .alert("暂未完成", isPresented: Binding(get: { store.error != nil && !store.showSettings && !store.showNewGroup }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if store.hasOlder {
                        Button(store.loadingOlder ? "正在加载…" : "加载更早的消息") { Task { await store.loadOlder() } }
                            .disabled(store.loadingOlder).buttonStyle(.borderless).padding(.top, 12)
                    }
                    if store.messages.isEmpty && store.currentPending.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 44, weight: .light)).foregroundStyle(accent)
                            Text("从一句话开始").font(.title3.bold())
                            Text("选择 Agent 开始私聊，\n或在群聊中 @指定 Agent。").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 100)
                    }
                    ForEach(store.messages) { message in
                        bubble(text: message.text, sender: message.sender, detail: (message.role == "assistant" ? "Agent · " : "") + message.date.formatted(date: .abbreviated, time: .shortened), mine: message.deviceId == store.deviceId, agentId: message.agentId)
                            .id(message.id)
                    }
                    ForEach(store.currentPending) { message in
                        VStack(alignment: .trailing, spacing: 6) {
                            bubble(text: message.text, sender: message.sender, detail: store.sending.contains(message.id) ? "发送中…" : "尚未确认送达服务器", mine: true)
                            if !store.sending.contains(message.id) {
                                Button("重试发送") { Task { await store.retry(message) } }.buttonStyle(.borderless)
                            }
                        }
                    }
                    ForEach(store.jobs) { job in
                        HStack(alignment: .top) {
                            Image(systemName: job.status == "FAILED" ? "exclamationmark.bubble" : "ellipsis.bubble")
                            Text("\(job.agentName) · \(job.status == "FAILED" ? job.error : job.status == "RUNNING" ? "正在回复…" : "等待回复…")").font(.caption)
                            Spacer()
                            if job.status == "FAILED" { Button("重试回复") { Task { await store.retryJob(job) } }.buttonStyle(.borderless) }
                        }.foregroundStyle(.secondary).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(26)
            }
            .onChange(of: store.messages.last?.id) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.currentPending.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func bubble(text: String, sender: String, detail: String, mine: Bool, agentId: String? = nil) -> some View {
        HStack {
            if mine { Spacer(minLength: 70) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if let agentId { AgentAvatarView(store: store, avatarId: store.avatarId(for: agentId), size: 28) }
                    Text(sender).font(.caption).foregroundStyle(.secondary)
                }
                Text(text).textSelection(.enabled).font(.system(size: 14)).lineSpacing(5).padding(.horizontal, 16).padding(.vertical, 12)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .background(mine ? accent : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: 540, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: 70) }
        }
    }
}

@MainActor
final class ConnectionDraft: ObservableObject {
    @Published var address = ""
    @Published var token = ""
    @Published var sender = ""
}

struct ConnectionView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = ConnectionDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("连接你的设备").font(.title2.bold())
            Text("两端使用相同的服务地址和访问令牌。令牌保存在 macOS 钥匙串中。").foregroundStyle(.secondary)
            Form {
                TextField("服务地址", text: $draft.address)
                SecureField("访问令牌", text: $draft.token)
                TextField("设备名称", text: $draft.sender)
            }.textFieldStyle(.roundedBorder)
            if let error = store.error { Text(error).font(.callout).foregroundStyle(.red) }
            Text("仅在应用打开且处于前台时自动接收。退出后，消息仍会保存在服务器。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { store.error = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.configuring { ProgressView().controlSize(.small) }
                Button("验证并连接") { Task { await store.configure(address: draft.address, token: draft.token, sender: draft.sender) } }
                    .buttonStyle(.borderedProminent).disabled(store.configuring)
            }
        }.padding(30).frame(width: 440)
        .onAppear { draft.address = store.address; draft.sender = store.sender; draft.token = Keychain.read() }
        .interactiveDismissDisabled(store.configuring)
    }
}

@MainActor
final class GroupDraft: ObservableObject {
    @Published var name = ""
    @Published var agentIds = Set<String>()
    @Published var creating = false
}
struct NewGroupView: View {
    @ObservedObject var store: ChatStore
    @StateObject private var draft = GroupDraft()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建群聊").font(.title2.bold())
            TextField("群聊名称", text: $draft.name).textFieldStyle(.roundedBorder)
            Text("选择加入群聊的 Agent").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.agents.filter { $0.enabled }) { agent in
                        Toggle("\(agent.name)  @\(agent.handle)", isOn: Binding(get: { draft.agentIds.contains(agent.id) }, set: { if $0 { draft.agentIds.insert(agent.id) } else { draft.agentIds.remove(agent.id) } }))
                    }
                }
            }.frame(maxHeight: 240)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { store.error = nil; dismiss() }.disabled(draft.creating)
                Spacer()
                Button(draft.creating ? "创建中…" : "创建群聊") {
                    draft.creating = true
                    Task { await store.createGroup(name: draft.name, agentIds: draft.agentIds.sorted()); draft.creating = false }
                }.buttonStyle(.borderedProminent).disabled(draft.creating || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.utf16.count > 60 || draft.agentIds.count > 32)
            }
        }.padding(28).frame(width: 380).interactiveDismissDisabled(draft.creating)
    }
}

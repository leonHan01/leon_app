import SwiftUI
import UIKit

@MainActor
struct NativeRootView: View {
    enum Route: Hashable { case chat, agent(String), usage }
    @ObservedObject var store: ChatStore
    @State private var tab = 0
    @State private var path: [Route] = []
    @State private var login = false
    @State private var group = false
    @State private var logout = false
    @State private var navigation = UUID()
    var body: some View {
        NavigationStack(path:$path) {
            TabView(selection:$tab) {
                List {
                    if store.agents.isEmpty { Text(store.loggedIn ? "还没有 Agents，请先在服务端配置。" : "先到设置中注册或登录。").foregroundStyle(.secondary) }
                    ForEach(store.agents.filter { agent in agent.enabled || store.conversations.contains(where:{$0.direct && $0.agentId == agent.id})}) { agent in
                        Button { openAgent(agent) } label: {
                            HStack(spacing:13) { AgentAvatar(store:store,agent:agent,size:48); VStack(alignment:.leading,spacing:6) { Text(agent.name).foregroundStyle(.primary); Text("@\(agent.handle) · \(agent.enabled ? agent.provider : "已停用")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                    }
                }.listStyle(.plain).tabItem { Label("Agents",systemImage:"person.2") }.tag(0)
                List {
                    if store.conversations.filter({!$0.direct}).isEmpty { Text("还没有群聊，点击右上角 ＋ 创建。").foregroundStyle(.secondary) }
                    ForEach(store.conversations.filter {!$0.direct}) { room in
                        Button { openRoom(room) } label: { Label(room.name,systemImage:"person.3").padding(.vertical,8) }.foregroundStyle(.primary)
                    }
                }.listStyle(.plain).tabItem { Label("群聊",systemImage:"bubble.left.and.bubble.right") }.tag(1)
                List {
                    Section { Label { VStack(alignment:.leading) { Text("Leon").font(.title2.bold()); Text("你的 Agents 与群聊").foregroundStyle(.secondary) } } icon: { Image(systemName:"message.fill").foregroundStyle(.green) } }
                    Section {
                        if let user = store.user { LabeledContent("UserName",value:user.username); Text(store.server).font(.caption).textSelection(.enabled); Button("退出登录",role:.destructive) { logout = true }.disabled(store.configuring) }
                        else { Button("注册或登录") { login = true } }
                    }
                    Section {
                        Button("Token 用量") { path.append(.usage) }.disabled(!store.loggedIn)
                        LabeledContent("连接状态",value:store.status)
                        Button("立即同步") { store.refresh(); Task { await store.refreshDirectory() } }.disabled(!store.loggedIn)
                    }
                    Section { Text("Leon iOS · 0.12.0"); Text("前台自动同步，后台暂停。消息保留在服务器，下次打开继续读取。").font(.caption).foregroundStyle(.secondary) }
                }.tabItem { Label("设置",systemImage:"gearshape") }.tag(2)
            }
            .navigationTitle(["Agents","群聊","设置"][tab]).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tab == 1 { Button { group = true } label: { Image(systemName:"plus") }.accessibilityLabel("新建群聊").disabled(!store.loggedIn || store.busy != nil) }
                else if tab == 0 { Button { Task { await store.refreshDirectory() } } label: { Image(systemName:"arrow.clockwise") }.accessibilityLabel("刷新 Agents").disabled(!store.loggedIn) }
            }
            .safeAreaInset(edge:.top,spacing:0) { if !store.connected && tab != 2 { Text(store.loggedIn ? store.status : "请先在设置中注册或登录").font(.caption).frame(maxWidth:.infinity).padding(8).background(Color.orange.opacity(0.12)) } }
            .navigationDestination(for:Route.self) { route in
                switch route {
                case .chat: NativeChatView(store:store,openRoom:openRoom,openAgent:{path.append(.agent($0))},openUsage:{path.append(.usage)})
                case .agent(let id): AgentProfileView(store:store,id:id,openRoom:openRoom,openAgent:openAgent)
                case .usage: UsageView(store:store)
                }
            }
        }
        .tint(.green)
        .sheet(isPresented:$login) { LoginView(store:store) }
        .sheet(isPresented:$group) {
            let token = navigation
            GroupForm(store:store) { name,agents,users in
                let result = await store.tool("正在创建群聊…") { try await $0.group(name:name,agentIds:agents,usernames:users) }
                guard let result else { return false }; store.upsert(result)
                if token == navigation && tab == 1 && path.isEmpty { openRoom(result) }
                return true
            }
        }
        .confirmationDialog("退出当前账号？",isPresented:$logout,titleVisibility:.visible) { Button("退出登录",role:.destructive) { Task { await store.logout() } }; Button("取消",role:.cancel) {} } message: { Text("下次登录需要重新输入服务访问令牌。") }
        .alert("暂未完成",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of:tab) { _ in navigation = UUID() }
        .onChange(of:path) { _ in navigation = UUID() }
        .onChange(of:store.user?.id) { id in if id == nil { path = []; tab = 2; login = false } else { tab = 0; login = false } }
        .onAppear { if !store.loggedIn { tab = 2 } }
    }
    private func openRoom(_ room: Conversation) {
        store.select(room.id)
        if let index = path.firstIndex(of:.chat) { path = Array(path.prefix(index+1)) }
        else { path.append(.chat) }
    }
    private func openAgent(_ agent: AgentInfo) { store.navigate(to:agent); if let index = path.firstIndex(of:.chat) { path = Array(path.prefix(index+1)) } else { path.append(.chat) } }
}
@MainActor
struct LoginView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("账号") { TextField("UserName",text:$name).textInputAutocapitalization(.never).autocorrectionDisabled(); Text("新用户名会自动注册，App 会记住当前登录状态。").font(.caption).foregroundStyle(.secondary) }
                Section("连接") { TextField("HTTPS 服务地址",text:$address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(); SecureField("服务访问令牌",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.disabled(store.configuring)
                .navigationTitle("注册或登录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(store.configuring) }; ToolbarItem(placement:.confirmationAction) { Button(store.configuring ? "登录中…" : "继续") { Task { if await store.login(address:address,serviceToken:token,username:name) { dismiss() } } }.disabled(store.configuring || token.isEmpty || name.isEmpty) } }
        }.onAppear { address = store.server }.interactiveDismissDisabled(store.configuring)
    }
}
@MainActor
struct GroupForm: View {
    @ObservedObject var store: ChatStore
    var submit: (String,[String],[String]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var users = ""
    @State private var selected = Set<String>()
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("群名称",text:$name); TextField("成员 UserName，用逗号分隔，可选",text:$users).textInputAutocapitalization(.never) }
                Section("选择 Agent（最多 32 个）") {
                    ForEach(store.agents.filter(\.enabled)) { agent in Toggle(agent.name,isOn:Binding(get:{selected.contains(agent.id)},set:{if $0 {selected.insert(agent.id)} else {selected.remove(agent.id)}})) }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.disabled(working).navigationTitle("新建群聊").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(working) }; ToolbarItem(placement:.confirmationAction) { Button("创建") { Task { working = true; defer {working = false}; if await submit(name.trimmingCharacters(in:.whitespacesAndNewlines),Array(selected),usernames(users)) { dismiss() } } }.disabled(working || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.utf16.count > 60 || selected.count > 32 || usernames(users).count > 32) } }
        }.interactiveDismissDisabled(working)
    }
}
func usernames(_ value: String) -> [String] { Array(Set(value.components(separatedBy:CharacterSet(charactersIn:",，")).map {$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter {!$0.isEmpty})).sorted() }
@MainActor
struct NamePrompt: View {
    let title: String
    let note: String
    var initial = "新对话"
    var submit: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var working = false
    var body: some View {
        NavigationStack { Form { Text(note).font(.caption); TextField("名称",text:$name); if working {ProgressView()} }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") {dismiss()}.disabled(working) }
                ToolbarItem(placement:.confirmationAction) { Button("创建") {Task {working = true; defer {working = false}; if await submit(name.trimmingCharacters(in:.whitespacesAndNewlines)) {dismiss()} }}.disabled(working || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.utf16.count > 60) }
            }
        }.onAppear {name = initial}.interactiveDismissDisabled(working)
    }
}
@MainActor
struct AgentProfileView: View {
    @ObservedObject var store: ChatStore
    let id: String
    var openRoom: (Conversation) -> Void
    var openAgent: (AgentInfo) -> Void
    @State private var create = false
    @State private var requestID = UUID().uuidString.lowercased()
    var body: some View {
        List {
            if let agent = store.agent(id) {
                Section {
                    HStack { AgentAvatar(store:store,agent:agent,size:64); VStack(alignment:.leading) {Text(agent.name).font(.title2);Text("@\(agent.handle)").foregroundStyle(.secondary)} }
                    Text(agent.description?.isEmpty == false ? agent.description! : "暂无介绍").textSelection(.enabled)
                    Text("\(agent.provider) · \(agent.model ?? "未提供模型信息")").font(.caption).textSelection(.enabled)
                    Button("继续聊天") {openAgent(agent)}.disabled(!agent.enabled)
                }
                Section("历史独立对话") {
                    Button("＋ 新建对话") {requestID = UUID().uuidString.lowercased();create = true}.disabled(!agent.enabled)
                    ForEach(store.conversations.filter {$0.direct && $0.agentId == id}) {room in Button(room.name) {openRoom(room)} }
                }
            } else { Text("Agent 暂不可用").foregroundStyle(.secondary) }
        }.navigationTitle("Agent 主页").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$create) { NamePrompt(title:"新建独立对话",note:"新对话从空白开始，原对话保留在主页。") {name in
                guard let result = await store.tool("正在新建对话…",work:{try await $0.newThread(agent:id,name:name,requestId:requestID)}) else {return false}
                store.upsert(result); openRoom(result);return true
            } }
    }
}
@MainActor
struct UsageView: View {
    @ObservedObject var store: ChatStore
    var body: some View {
        List {
            Section { Text("当前用户触发的 Agent 回复、上下文压缩与归档用量。群聊用量计入发起者。").font(.caption); if store.loadingUsage {ProgressView()};if let error = store.usageError {Text(error).foregroundStyle(.red)} }
            if let date = store.usageLoadedAt {
                Section("累计") {
                    Text("总 Token  \(store.usage.reduce(Int64(0)) {$0+$1.totalTokens})").font(.title2)
                    Text("输入 \(store.usage.reduce(Int64(0)) {$0+$1.inputTokens}) · 输出 \(store.usage.reduce(Int64(0)) {$0+$1.outputTokens})")
                    Text("已报告 \(store.usage.reduce(Int64(0)) {$0+$1.reportedCalls}) 次 · 未报告 \(store.usage.reduce(Int64(0)) {$0+$1.unreportedCalls}) 次").font(.caption)
                    let costs = store.usage.compactMap { UsagePricing.estimate($0) }
                    if !costs.isEmpty { Text("已匹配模型估算 \(UsagePricing.label(.init(low:costs.reduce(0){$0+$1.low},high:costs.reduce(0){$0+$1.high}))) USD") }
                    if costs.count < store.usage.count {Text("部分模型暂无可匹配价格，未计入金额。").font(.caption)}
                    Text("读取于 \(date.formatted())").font(.caption).foregroundStyle(.secondary)
                }
                if store.usage.isEmpty { Text("暂无用量记录") }
                ForEach(store.usage) {row in Section("\(row.provider) · \(row.model)") {Text("输入 \(row.inputTokens) · 输出 \(row.outputTokens) · 合计 \(row.totalTokens)");Text("已报告 \(row.reportedCalls) 次 · 未报告 \(row.unreportedCalls) 次").font(.caption); if let cost = UsagePricing.estimate(row) {Text("估算 \(UsagePricing.label(cost)) USD")} else {Text("暂无可匹配价格")} } }
            }
            Section { Text("沿用 2026-11-19 价格表，按全部命中 / 未命中缓存及 DeepSeek 非高峰 / 高峰估算。历史价格、缓存细分和未报告调用无法还原，金额不是账单。").font(.caption).foregroundStyle(.secondary);Link("OpenAI 价格",destination:URL(string:"https://developers.openai.com/api/docs/pricing")!);Link("DeepSeek 价格",destination:URL(string:"https://api-docs.deepseek.com/quick_start/pricing/")!) }
        }.navigationTitle("Token 用量").navigationBarTitleDisplayMode(.inline).task {await store.loadUsage()}.toolbar {Button {Task {await store.loadUsage()}} label:{Image(systemName:"arrow.clockwise")}.disabled(store.loadingUsage)}
    }
}

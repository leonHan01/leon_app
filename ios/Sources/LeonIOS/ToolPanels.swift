import SwiftUI

@MainActor
struct ContextPanel: View {
    @ObservedObject var store: ChatStore
    let room: String
    @State private var info: ConversationContext?
    @State private var rounds = 10
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {Form {
            Stepper("保留最近 \(rounds) 轮完整对话",value:$rounds,in:1...20)
            if let info {
                Text("输入预算：\(info.inputTokenBudget) Token")
                ForEach(info.agents) {agent in Section(agent.agentName) {Text("最近约 \(agent.estimatedInputTokens) Token · \(agent.retainedRounds) 轮").font(.caption);Text(agent.summary.isEmpty ? "尚无压缩摘要" : agent.summary).textSelection(.enabled)} }
            } else {ProgressView()}
            if let error = store.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("查看上下文").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("关闭") {dismiss()}};ToolbarItem(placement:.primaryAction) {Button("刷新") {Task {await refresh()}}.disabled(store.busy != nil)};ToolbarItem(placement:.confirmationAction) {Button("保存") {Task {if await store.tool("正在保存轮数…",work:{try await $0.configureContext(room:room,rounds:rounds)}) != nil {dismiss()}}}.disabled(store.busy != nil || info == nil)}}
        }.task {await refresh()}
    }
    private func refresh() async {if let result = await store.tool("正在读取上下文…",work:{try await $0.context(room:room)}) {info = result;rounds = max(1,min(20,result.recentRounds))}}
}
@MainActor
struct ClearPanel: View {
    @ObservedObject var store: ChatStore
    let preview: ClearHistoryPreview
    var backup: () -> Void
    @State private var request = UUID().uuidString.lowercased()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {Form {
            Text("将永久删除「\(preview.conversationName)」的 \(preview.messageCount) 条消息、图片和上下文，并同步至所有设备。")
            Button("先备份",action:backup)
            Button("永久清理",role:.destructive) {Task {
                guard store.sending.isEmpty, !store.savingDraft, store.preparingImages == 0 else {store.error = "请等待发送和图片处理完成。";return}
                let connection = store.connectionID
                if let result = await store.tool("正在清理记录…",work:{try await $0.clear(preview,requestId:request)}), connection == store.connectionID, preview.conversationId == store.roomID {
                    do {try await store.clearLocal(preview.conversationId,revision:result.historyRevision);dismiss()} catch {store.error = error.localizedDescription}
                }
            }}.disabled(store.busy != nil)
            if let error = store.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("清理聊天记录？").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}}}
    }
}
@MainActor
struct RestorePanel: View {
    @ObservedObject var store: ChatStore
    let info: BackupPreview
    let bytes: Data
    let agent: String?
    let request: String
    var restored: (Conversation) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {Form {
            Text("「\(info.name)」\n\(info.messageCount) 条消息")
            Text("恢复文字、图片和上下文，创建独立对话；已有记录保留，不自动调用模型。").font(.caption)
            Button("加载为新对话") {Task {if let result = await store.tool("正在加载备份…",work:{try await $0.restore(bytes,agent:agent,requestId:request)}) {restored(result);dismiss()}}}.disabled(store.busy != nil)
            if let error = store.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("加载聊天备份").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}.disabled(store.busy != nil)}}}.interactiveDismissDisabled(store.busy != nil)
    }
}
@MainActor
struct MembersPanel: View {
    @ObservedObject var store: ChatStore
    let room: Conversation
    @State private var users: [ChatUser] = []
    @State private var names = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {List {
            Section("会话 Agent") {ForEach(store.agents.filter {room.agentIds.contains($0.id) || room.id == "shared" || room.id.hasPrefix("home:")}) {agent in HStack {AgentAvatar(store:store,agent:agent,size:32);Text(agent.name);Text("@\(agent.handle)").font(.caption).foregroundStyle(.secondary)}}}
            if room.kind == "group" {
                Section("群成员") {ForEach(users,id:\.id) {Text($0.username)}}
                if store.owns(room), room.id != "shared", !room.id.hasPrefix("home:") {Section("添加已注册用户") {TextField("UserName，用逗号分隔",text:$names).textInputAutocapitalization(.never);Button("添加用户") {Task {if let result = await store.tool("正在添加群成员…",work:{try await $0.members(room:room.id,adding:usernames(names))}) {users = result;names = ""}}}.disabled(usernames(names).isEmpty || usernames(names).count > 32 || store.busy != nil)}}
            }
            if let error = store.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle(room.name).navigationBarTitleDisplayMode(.inline).toolbar {Button("关闭") {dismiss()}}}.task {if room.kind == "group", let result = await store.tool("正在读取群成员…",work:{try await $0.members(room:room.id,adding:nil)}) {users = result}}
    }
}

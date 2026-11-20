import SwiftUI

@MainActor
struct ContextPanel: View {
    @ObservedObject var store:ChatStore
    let room:String
    var close:()->Void
    @State private var info:ConversationContext?
    @State private var rounds = 10
    var body:some View {
        MobileDialog(title:"查看上下文",close:close) {
            VStack(alignment:.leading,spacing:12) {
                Text("保留最近 \(rounds) 轮完整对话").font(.system(size:14))
                Stepper("保留轮数",value:$rounds,in:1...20).labelsHidden().disabled(store.busy != nil).accessibilityLabel("保留最近 \(rounds) 轮完整对话")
                if let info {
                    Text("输入预算：\(info.inputTokenBudget) Token").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                    ForEach(info.agents) {agent in
                        VStack(alignment:.leading,spacing:6) {
                            Text(agent.agentName).font(.system(size:15,weight:.bold))
                            Text("最近约 \(agent.estimatedInputTokens) Token · \(agent.retainedRounds) 轮").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                            Text(agent.summary.isEmpty ? "尚无压缩摘要" : agent.summary).font(.system(size:14)).textSelection(.enabled)
                        }.padding(.top,8)
                    }
                } else if store.busy != nil {ProgressView()} else {Text("读取失败，请刷新重试。").font(.system(size:14)).foregroundStyle(MobileStyle.muted)}
            }.padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"刷新") {Task {await refresh()}}.disabled(store.busy != nil)
            MobileTextButton(title:"关闭",action:close)
            MobileTextButton(title:"保存") {Task {if await store.tool("正在保存上下文设置…",work:{try await $0.configureContext(room:room,rounds:rounds)}) != nil {close()}}}.disabled(store.busy != nil || info == nil)
        }.task {await refresh()}
    }
    private func refresh() async {if let result = await store.tool("正在读取上下文…",work:{try await $0.context(room:room)}) {info = result;rounds = max(1,min(20,result.recentRounds))}}
}
@MainActor
struct ClearPanel: View {
    @ObservedObject var store:ChatStore
    let preview:ClearHistoryPreview
    var backup:()->Void
    var close:()->Void
    @State private var request = UUID().uuidString.lowercased()
    var body:some View {
        MobileDialog(title:"清理聊天记录？",close:{if store.busy == nil {close()}}) {
            Text("将永久删除「\(preview.conversationName)」的 \(preview.messageCount) 条消息、图片和上下文，并同步至所有设备。").font(.system(size:14)).padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"先备份",action:backup).disabled(store.busy != nil)
            MobileTextButton(title:"取消",action:close).disabled(store.busy != nil)
            MobileTextButton(title:"永久清理",destructive:true) {Task {
                guard store.sending.isEmpty,!store.savingDraft,store.preparingImages == 0 else {store.error = "请等待发送和图片处理完成。";return}
                let connection = store.connectionID
                if let result = await store.tool("正在清理记录…",work:{try await $0.clear(preview,requestId:request)}),connection == store.connectionID,preview.conversationId == store.roomID {
                    do {try await store.clearLocal(preview.conversationId,revision:result.historyRevision);close()} catch {store.error = error.localizedDescription}
                }
            }}.disabled(store.busy != nil)
        }
    }
}
@MainActor
struct RestorePanel: View {
    @ObservedObject var store:ChatStore
    let info:BackupPreview
    let bytes:Data
    let agent:String?
    let request:String
    var close:()->Void
    var restored:(Conversation)->Void
    var body:some View {
        MobileDialog(title:"加载聊天备份",close:{if store.busy == nil {close()}}) {
            VStack(alignment:.leading,spacing:12) {
                Text("「\(info.name)」\n\(info.messageCount) 条消息").font(.system(size:15))
                Text("恢复文字、图片和上下文，创建独立对话；已有记录保留，不自动调用模型。").font(.system(size:13)).foregroundStyle(MobileStyle.muted)
                if store.busy != nil {ProgressView()}
            }.padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(store.busy != nil)
            MobileTextButton(title:"加载为新对话") {Task {if let result = await store.tool("正在加载备份…",work:{try await $0.restore(bytes,agent:agent,requestId:request)}) {restored(result);close()}}}.disabled(store.busy != nil)
        }
    }
}
@MainActor
struct MembersPanel: View {
    @ObservedObject var store:ChatStore
    let room:Conversation
    var showMembers = false
    var close:()->Void
    @State private var users:[ChatUser] = []
    @State private var names = ""
    var body:some View {
        MobileDialog(title:showMembers ? "群成员" : "会话信息",close:close) {
            VStack(alignment:.leading,spacing:0) {
                Text(showMembers ? room.name : store.status).font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.vertical,6)
                if showMembers {
                    if store.busy != nil {ProgressView().padding(.vertical,8)}
                    ForEach(users,id:\.id) {user in Text(user.username).font(.system(size:15)).padding(.vertical,12)}
                    if store.owns(room),room.id != "shared",!room.id.hasPrefix("home:") {
                        MobileField(label:"添加已注册用户（用逗号分隔）") {TextField("UserName",text:$names).textInputAutocapitalization(.never).autocorrectionDisabled()}
                    }
                } else {
                    ForEach(store.agents.filter {room.agentIds.contains($0.id) || room.id == "shared" || room.id.hasPrefix("home:")}) {agent in
                        HStack(spacing:10) {AgentAvatar(store:store,agent:agent,size:36);Text("\(agent.name)  @\(agent.handle)").font(.system(size:14))}.padding(.top,12).padding(.bottom,8)
                    }
                }
            }
        } actions:{
            if showMembers,store.owns(room),room.id != "shared",!room.id.hasPrefix("home:") {
                MobileTextButton(title:"添加用户") {Task {if let result = await store.tool("正在添加群成员…",work:{try await $0.members(room:room.id,adding:usernames(names))}) {users = result;names = ""}}}.disabled(usernames(names).isEmpty || usernames(names).count>32 || store.busy != nil)
            }
            MobileTextButton(title:"关闭",action:close)
        }.task {if showMembers,let result = await store.tool("正在读取群成员…",work:{try await $0.members(room:room.id,adding:nil)}) {users = result}}
    }
}

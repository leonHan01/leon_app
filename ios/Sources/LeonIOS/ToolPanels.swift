import SwiftUI

@MainActor
struct ContextPanel: View {
    @ObservedObject var store:ChatStore
    let room:String
    var close:()->Void
    @State private var info:ConversationContext?
    var body:some View {
        MobileDialog(title:"查看上下文",close:close) {
            VStack(alignment:.leading,spacing:12) {
                if let info {
                    Text(info.compressionMode == "token" ? "按 Token 预算管理上下文，不再按对话轮数自动压缩。" : "当前服务端尚未提供新版记忆策略，请升级服务端。").font(.system(size:13)).foregroundStyle(MobileStyle.muted)
                    Text("输入预算：\(info.inputTokenBudget) Token").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                    ForEach(info.agents) {agent in
                        VStack(alignment:.leading,spacing:6) {
                            Text(agent.agentName).font(.system(size:15,weight:.bold))
                            Text("最近约 \(agent.estimatedInputTokens) Token · \(agent.retainedRounds) 轮").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                            if let count = agent.retrievedRounds, count > 0 {Text("最近检索了 \(count) 轮相关历史原文").font(.system(size:12)).foregroundStyle(MobileStyle.muted)}
                            if agent.compressionFallback == true {Text("最近请求使用了完整原文回退").font(.system(size:12)).foregroundStyle(MobileStyle.muted)}
                            Text("已确认事实").font(.system(size:14,weight:.semibold))
                            if (agent.facts ?? []).isEmpty {Text("压缩时提取有用户原文依据的事实。").font(.system(size:12)).foregroundStyle(MobileStyle.muted)}
                            ForEach(agent.facts ?? []) {fact in
                                Text("\(fact.speaker)：\(fact.value) · 来源 #\(fact.sourceMessageId)").font(.system(size:13)).textSelection(.enabled)
                            }
                            Text("阶段摘要").font(.system(size:14,weight:.semibold))
                            Text(agent.summary.isEmpty ? "尚无压缩摘要" : agent.summary).font(.system(size:14)).textSelection(.enabled)
                        }.padding(.top,8)
                    }
                } else if store.busy != nil {ProgressView()} else {Text("读取失败，请刷新重试。").font(.system(size:14)).foregroundStyle(MobileStyle.muted)}
            }.padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"刷新") {Task {await refresh()}}.disabled(store.busy != nil)
            MobileTextButton(title:"关闭",action:close)
        }.task {await refresh()}
    }
    private func refresh() async {if let result = await store.tool("正在读取上下文…",work:{try await $0.context(room:room)}) {info = result}}
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
                    do {try await store.clearLocal(preview.conversationId,revision:result.historyRevision);store.showNotice("聊天记录已清理");close()} catch {store.error = error.localizedDescription}
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
            MobileTextButton(title:"加载为新对话") {Task {if let result = await store.tool("正在加载备份…",work:{try await $0.restore(bytes,agent:agent,requestId:request)}) {restored(result);store.showNotice("备份已加载");close()}}}.disabled(store.busy != nil)
        }
    }
}
@MainActor
struct MembersPanel: View {
    @ObservedObject var store:ChatStore
    let room:Conversation
    var showMembers = false
    var close:()->Void
    var addUsers:(()->Void)? = nil
    var addAgents:(()->Void)? = nil
    @State private var users:[ChatUser] = []
    private var current:Conversation {store.conversations.first {$0.id == room.id} ?? room}
    private var agents:[AgentInfo] {store.agents.filter {current.agentIds.contains($0.id) || current.id == "shared" || current.id.hasPrefix("home:")}}
    var body:some View {
        MobileDialog(title:showMembers ? "群成员" : "会话信息",close:close) {
            VStack(alignment:.leading,spacing:0) {
                Text(showMembers ? room.name : store.status).font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.vertical,6)
                if showMembers {
                    if store.busy != nil {ProgressView().padding(.vertical,8)}
                    Text("用户").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,8)
                    ForEach(users,id:\.id) {user in Text(user.username).font(.system(size:15)).padding(.vertical,12)}
                    Text("Agent · \(agents.count)").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,8)
                    ForEach(agents) {agent in
                        HStack(spacing:10) {AgentAvatar(store:store,agent:agent,size:32);Text("\(agent.name)  @\(agent.handle)").font(.system(size:14))}.padding(.vertical,8)
                    }
                    if store.managesGroup(current) {
                        HStack {
                            if let addUsers {MobileTextButton(title:"添加用户",action:addUsers)}
                            if let addAgents {MobileTextButton(title:"添加 Agent",action:addAgents)}
                        }.disabled(store.busy != nil).padding(.top,8)
                    }
                } else {
                    ForEach(store.agents.filter {room.agentIds.contains($0.id) || room.id == "shared" || room.id.hasPrefix("home:")}) {agent in
                        HStack(spacing:10) {AgentAvatar(store:store,agent:agent,size:36);Text("\(agent.name)  @\(agent.handle)").font(.system(size:14))}.padding(.top,12).padding(.bottom,8)
                    }
                }
            }
        } actions:{
            MobileTextButton(title:"关闭",action:close)
        }.task {if showMembers,let result = await store.tool("正在读取群成员…",work:{try await $0.members(room:room.id,adding:nil)}) {users = result}}
    }
}

@MainActor
struct InviteUsersPanel:View {
    @ObservedObject var store:ChatStore
    let room:Conversation
    var close:()->Void
    @State private var names = ""
    private var current:Conversation {store.conversations.first {$0.id == room.id} ?? room}
    var body:some View {
        MobileDialog(title:"添加用户",close:{if store.busy == nil {close()}}) {
            VStack(alignment:.leading,spacing:10) {
                Text("添加到「\(room.name)」").font(.system(size:14))
                MobileField(label:"已注册的 UserName（用逗号分隔）") {TextField("UserName",text:$names).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("group_invite_usernames")}
                Text("每次最多添加 32 位用户。已在群内的用户不会重复添加。").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
            }.padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(store.busy != nil)
            MobileTextButton(title:"添加") {Task {
                if await store.tool("正在添加群成员…",work:{try await $0.members(room:room.id,adding:usernames(names))}) != nil {store.showNotice("用户已加入群聊");close()}
            }}.disabled(!store.managesGroup(current) || usernames(names).isEmpty || usernames(names).count>32 || store.busy != nil)
        }
    }
}

@MainActor
struct InviteAgentsPanel:View {
    @ObservedObject var store:ChatStore
    let room:Conversation
    var close:()->Void
    @State private var selected = Set<String>()
    private var current:Conversation {store.conversations.first {$0.id == room.id} ?? room}
    private var candidates:[AgentInfo] {store.agents.filter {$0.enabled && !current.agentIds.contains($0.id)}}
    private var additions:[String] {candidates.filter {selected.contains($0.id)}.map(\.id)}
    private var remaining:Int {max(0,32-current.agentIds.count)}
    var body:some View {
        MobileDialog(title:"添加 Agent",close:{if store.busy == nil {close()}}) {
            VStack(alignment:.leading,spacing:8) {
                Text("「\(room.name)」已加入 \(current.agentIds.count) / 32 位 Agent，可多选").font(.system(size:13)).foregroundStyle(MobileStyle.muted)
                if candidates.isEmpty {Text("暂无可添加的 Agent").font(.system(size:14)).padding(.vertical,12)}
                ForEach(candidates) {agent in
                    Button {if !selected.insert(agent.id).inserted {selected.remove(agent.id)}} label:{
                        HStack(spacing:10) {
                            Image(systemName:selected.contains(agent.id) ? "checkmark.square.fill" : "square").foregroundStyle(selected.contains(agent.id) ? MobileStyle.green : MobileStyle.muted)
                            AgentAvatar(store:store,agent:agent,size:32)
                            Text("\(agent.name)  @\(agent.handle)").font(.system(size:14)).frame(maxWidth:.infinity,alignment:.leading)
                        }.foregroundStyle(MobileStyle.ink).padding(.vertical,8).contentShape(Rectangle())
                    }.buttonStyle(MobilePressStyle()).disabled(store.busy != nil || (!selected.contains(agent.id) && additions.count>=remaining)).accessibilityIdentifier("invite-agent:"+agent.id)
                }
                if remaining == 0 {Text("群聊最多加入 32 个 Agent").font(.system(size:12)).foregroundStyle(MobileStyle.muted)}
            }.padding(.vertical,6)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(store.busy != nil)
            MobileTextButton(title:"添加") {Task {
                if let result = await store.tool("正在添加 Agent…",work:{try await $0.addAgents(room:room.id,agentIds:additions)}) {store.upsert(result);store.showNotice("Agent 已加入群聊");close()}
            }}.disabled(!store.managesGroup(current) || additions.isEmpty || additions.count>remaining || store.busy != nil)
        }.task {await store.refreshDirectory()}
    }
}

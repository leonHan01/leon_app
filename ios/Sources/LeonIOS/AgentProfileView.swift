import SwiftUI

@MainActor
struct AgentProfileView: View {
    @ObservedObject var store: ChatStore
    let id: String
    var openRoom: (Conversation) -> Void
    var openAgent: (AgentInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var create = false
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var origin: ImageOrigin?
    @State private var visible = false
    private var rooms: [Conversation] {store.conversations.filter {$0.direct && $0.agentId == id}}
    var body: some View {
        VStack(spacing:0) {
            MobileHeader(title:"Agent 详情",back:{dismiss()}) {
                MobileIconButton(symbol:.refresh,label:"刷新 Agent 详情") {store.refresh();Task {await store.refreshDirectory()}}
            }
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    if let agent = store.agent(id) {
                        profile(agent)
                        HStack(spacing:0) {
                            Text("历史对话 · \(rooms.count)").font(.system(size:16,weight:.bold)).frame(maxWidth:.infinity,alignment:.leading)
                            MobileTextButton(title:"＋ 新建对话") {requestID = UUID().uuidString.lowercased();origin = store.imageOrigin;create = true}.disabled(!agent.enabled)
                        }.padding(.leading,2).padding(.top,2)
                        if rooms.isEmpty {Text("暂无历史对话，开始聊聊吧。").font(.system(size:14)).foregroundStyle(MobileStyle.muted).padding(.horizontal,4).padding(.vertical,24)}
                        ForEach(rooms) {room in
                            Button {openRoom(room)} label:{
                                HStack(spacing:12) {
                                    MobileIcon(symbol:.threads,color:MobileStyle.green)
                                    Text(room.name).font(.system(size:15)).frame(maxWidth:.infinity,alignment:.leading)
                                    MobileIcon(symbol:.chevron,size:18,color:MobileStyle.color(0xBBBBBB))
                                }.foregroundStyle(MobileStyle.ink).padding(.horizontal,14).padding(.vertical,16).background(.white,in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(MobilePressStyle(radius:14)).accessibilityIdentifier("agent-history:"+room.id)
                        }
                    } else {Text("Agent 已不存在，请返回列表刷新。").font(.system(size:15)).foregroundStyle(MobileStyle.muted)}
                }.padding(.horizontal,12).padding(.top,12).padding(.bottom,16)
            }
        }.background(MobileStyle.bar.ignoresSafeArea()).foregroundStyle(MobileStyle.ink).toolbar(.hidden,for:.navigationBar)
            .overlay {
                if create {
                    NamePrompt(title:"新建独立对话",note:"新对话从空白开始，原对话保留在主页。",close:{create = false}) {name in
                        guard let result = await store.tool("正在新建对话…",work:{try await $0.newThread(agent:id,name:name,requestId:requestID)}) else {return false}
                        store.upsert(result);if visible && origin == store.imageOrigin {openRoom(result)};return true
                    }
                }
            }.onAppear {visible = true}.onDisappear {visible = false}
    }
    private func profile(_ agent: AgentInfo) -> some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {
                AgentAvatar(store:store,agent:agent,size:48)
                VStack(alignment:.leading,spacing:4) {
                    Text(agent.name).font(.system(size:20,weight:.bold)).accessibilityIdentifier("agent_detail_name")
                    Text("@\(agent.handle)\(agent.enabled ? "" : " · 已停用")").font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Button {openAgent(agent)} label:{Text(rooms.isEmpty ? "开始聊天" : "继续聊天").font(.system(size:13)).foregroundStyle(.white).frame(width:80,height:48).background(MobileStyle.green,in:RoundedRectangle(cornerRadius:12))}
                    .buttonStyle(MobilePressStyle(radius:12)).disabled(!agent.enabled).opacity(agent.enabled ? 1 : 0.45).accessibilityIdentifier("agent_detail_chat")
            }
            detail("介绍",agent.description?.isEmpty == false ? agent.description! : "暂无介绍").padding(.top,14).accessibilityIdentifier("agent_detail_description")
            detail("模型","\(agent.provider) · \(agent.model?.isEmpty == false ? agent.model! : "未提供模型信息")").padding(.top,10).accessibilityIdentifier("agent_detail_model")
        }.padding(.horizontal,16).padding(.vertical,14).background(.white,in:RoundedRectangle(cornerRadius:14))
    }
    private func detail(_ title: String,_ value: String) -> some View {
        HStack(alignment:.top,spacing:0) {
            Text(title).font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,2).frame(width:40,alignment:.leading)
            Text(value).font(.system(size:14)).lineSpacing(3).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

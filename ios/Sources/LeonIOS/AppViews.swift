import SwiftUI
import UIKit

@MainActor
struct NativeRootView: View {
    enum Route: Hashable {case chat, agent(String)}
    @ObservedObject var store: ChatStore
    @State private var tab = 0
    @State private var path: [Route] = []
    @State private var login = false
    @State private var group = false
    @State private var usage = false
    @State private var logout = false
    @State private var connectionInfo = false
    @State private var searching = false
    @State private var favorites = false
    @State private var navigation = UUID()
    @State private var groupNavigation = UUID()
    private var directory: [AgentInfo] {store.agents.filter {agent in agent.enabled || store.conversations.contains {$0.direct && $0.agentId == agent.id}}}
    private var groups: [Conversation] {store.conversations.filter {!$0.direct}}
    var body: some View {
        NavigationStack(path:$path) {
            home
                .toolbar(.hidden,for:.navigationBar)
                .navigationDestination(for:Route.self) {route in
                    switch route {
                    case .chat: NativeChatView(store:store,openRoom:openRoom,openAgent:{path.append(.agent($0))},openUsage:{usage = true})
                    case .agent(let id): AgentProfileView(store:store,id:id,openRoom:openRoom,openAgent:openAgent)
                    }
                }
        }
        .fullScreenCover(isPresented:$searching) {
            ChatSearchView(store:store) { id in
                if let room = store.conversations.first(where:{$0.id == id}) {openRoom(room)}
                else {Task {await store.refreshDirectory();if let room = store.conversations.first(where:{$0.id == id}) {openRoom(room)}}}
            }
        }
        .fullScreenCover(isPresented:$favorites) {
            FavoritesView(store:store,openRoom:openRoom)
        }
        .tint(MobileStyle.green).preferredColorScheme(.light)
        .overlay {dialogs}
        .overlay(alignment:.bottom) {
            if let notice = store.notice {
                Text(notice.text).font(.system(size:13)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal,18).padding(.vertical,12).background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:9))
                    .padding(.horizontal,24).padding(.bottom,84).allowsHitTesting(false).id(notice.id)
            }
        }
        .modifier(NotificationHost(store:store,visibleRoom:path.last == .chat ? store.roomID : nil,openRoom:{id in
            Task {do {let room=try await store.conversationForOpening(id);openRoom(room)}catch {store.error=error.localizedDescription}}
        }))
        .onChange(of:store.notice?.id) {_ in if let notice = store.notice {UIAccessibility.post(notification:.announcement,argument:notice.text)}}
        .onChange(of:tab) {_ in navigation = UUID()}
        .onChange(of:path) {_ in navigation = UUID()}
        .onChange(of:store.user?.id) {id in
            path = [];tab = id == nil ? 2 : 0;login = false;group = false;usage = false;logout = false
        }
    }
    private var home: some View {
        VStack(spacing:0) {
            MobileHeader(title:["Agents","群聊","设置"][tab],home:true) {
                if tab == 1 {MobileIconButton(symbol:.plus,label:"新建群聊",action:showGroup).disabled(!store.loggedIn || store.busy != nil)}
                else if tab == 0 {
                    Menu {
                        Button("立即同步",action:sync)
                        Button("新建群聊",action:showGroup).disabled(!store.loggedIn)
                    } label:{MobileIcon(symbol:.more).frame(width:44,height:44).contentShape(Rectangle())}
                        .accessibilityLabel("列表操作")
                }
            }
            if !store.connected && tab != 2 {
                Text(store.loggedIn ? store.status : "请先在设置中注册或登录")
                    .font(.system(size:12)).foregroundStyle(MobileStyle.muted).frame(maxWidth:.infinity,alignment:.leading)
                    .padding(.horizontal,18).padding(.vertical,9).background(MobileStyle.color(0xFFF6E8))
            }
            if tab != 2 {
                Button {searching = true} label:{
                    HStack(spacing:8) {Image(systemName:"magnifyingglass");Text("搜索聊天记录").font(.system(size:15))}.foregroundStyle(MobileStyle.muted).frame(maxWidth:.infinity).padding(10).background(.white,in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,9).background(MobileStyle.bar).disabled(!store.loggedIn).accessibilityIdentifier("global_chat_search")
            }
            ScrollView {
                LazyVStack(spacing:0) {
                    if tab == 0 {agentRows}
                    else if tab == 1 {groupRows}
                    else {settingsRows}
                }.frame(maxWidth:.infinity)
            }.background(.white).accessibilityIdentifier(tab == 0 ? "agent_list" : tab == 1 ? "group_list" : "settings_list")
            MobileDivider()
            HStack(spacing:0) {
                homeTab(0,"Agents",.agents)
                homeTab(1,"群聊",.groups)
                homeTab(2,"设置",.settings)
            }.frame(height:60).background(MobileStyle.bar)
        }.background(MobileStyle.bar.ignoresSafeArea()).foregroundStyle(MobileStyle.ink)
    }
    @ViewBuilder private var agentRows: some View {
        if directory.isEmpty {
            empty("还没有 Agents",store.loggedIn ? "在服务端配置 Agent 后，点这里即可开始私聊。" : "先连接服务，查看你的 AI 助手。")
        } else {
            ForEach(directory) {agent in
                DirectoryRow(title:agent.name,detail:"@\(agent.handle) · \(agent.enabled ? agent.provider : "已停用")",action:{openAgent(agent)}) {
                    AgentAvatar(store:store,agent:agent,size:48)
                }.accessibilityIdentifier("agent:"+agent.id)
            }
        }
    }
    @ViewBuilder private var groupRows: some View {
        if groups.isEmpty {
            empty("还没有群聊",store.loggedIn ? "点击右上角 ＋，选择 Agents 创建群聊。" : "连接服务后即可查看和创建群聊。")
        } else {
            ForEach(groups) {room in
                DirectoryRow(title:room.name,detail:room.id == "shared" || room.id.hasPrefix("home:") ? "设备消息与 Agent 群聊" : "\(room.agentIds.count) 位 Agent",action:{openRoom(room)}) {
                    MobileIcon(symbol:.groups,size:28,color:.white).frame(width:48,height:48).background(MobileStyle.color(0x62AA88),in:RoundedRectangle(cornerRadius:7))
                }.accessibilityIdentifier("group:"+room.id)
            }
        }
    }
    private var settingsRows: some View {
        VStack(spacing:0) {
            HStack(spacing:16) {
                Text("L").font(.system(size:25,weight:.bold)).foregroundStyle(.white).frame(width:58,height:58).background(MobileStyle.green,in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:7) {Text("Leon").font(.system(size:21,weight:.bold));Text("你的 Agents 与群聊").font(.system(size:13)).foregroundStyle(MobileStyle.muted)}
                Spacer(minLength:0)
            }.padding(.horizontal,20).padding(.vertical,26)
            sectionGap
            if let user = store.user {
                SettingRow(title:user.username,summary:store.server,symbol:.agents,action:{logout = true}).accessibilityIdentifier("connection_settings")
                SettingRow(title:"退出登录",symbol:.settings,action:{logout = true}).disabled(store.configuring)
            } else {
                SettingRow(title:"注册或登录",summary:"输入 UserName 和服务访问令牌",symbol:.agents,action:{login = true}).accessibilityIdentifier("connection_settings")
            }
            NotificationSettingsView()
            SettingRow(title:"收藏",summary:"查看收藏的消息与图片",symbol:.favorite,action:{favorites = true}).disabled(!store.loggedIn).accessibilityIdentifier("my_favorites")
            SettingRow(title:"Token 用量",summary:"查看累计消耗与模型明细",symbol:.usage,action:{usage = true}).accessibilityIdentifier("token_usage")
            sectionGap
            SettingRow(title:"连接状态",summary:store.connected ? "已连接 · 自动同步" : store.status,symbol:.groups,action:{connectionInfo = true})
            SettingRow(title:"立即同步",summary:"更新 Agents 与会话",symbol:.refresh,action:sync)
            sectionGap
            Text("Leon for iOS · \(MobileStyle.version)").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.horizontal,20).padding(.vertical,24)
        }
    }
    private var sectionGap: some View {MobileStyle.bar.frame(height:10)}
    private func homeTab(_ index: Int,_ title: String,_ symbol: MobileSymbol) -> some View {
        Button {tab = index;path = []} label:{
            VStack(spacing:4) {
                MobileIcon(symbol:symbol,color:tab == index ? MobileStyle.green : MobileStyle.ink)
                Text(title).font(.system(size:11)).foregroundStyle(tab == index ? MobileStyle.green : MobileStyle.muted)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
        }.buttonStyle(MobilePressStyle(radius:0)).accessibilityLabel(title).accessibilityAddTraits(tab == index ? .isSelected : []).accessibilityIdentifier("tab_"+["agents","groups","settings"][index])
    }
    private func empty(_ title: String,_ detail: String) -> some View {
        VStack(spacing:12) {
            Text(title).font(.system(size:18))
            Text(detail).font(.system(size:14)).foregroundStyle(MobileStyle.muted).lineSpacing(5).multilineTextAlignment(.center)
            if !store.loggedIn {MobileTextButton(title:"前往设置") {tab = 2}}
        }.frame(maxWidth:.infinity).padding(.horizontal,28).padding(.top,80).padding(.bottom,40)
    }
    @ViewBuilder private var dialogs: some View {
        ZStack {
            if login {LoginView(store:store,close:{login = false})}
            if group {GroupForm(store:store,close:{group = false}) {name,agents,users in
                let token = groupNavigation
                guard let result = await store.tool("正在创建群聊…",work:{try await $0.group(name:name,agentIds:agents,usernames:users)}) else {return false}
                store.upsert(result);store.showNotice("群聊已创建")
                if token == navigation && tab == 1 && path.isEmpty {openRoom(result)}
                return true
            }}
            if usage {UsageView(store:store,close:{usage = false})}
            if logout {
                MobileDialog(title:"退出当前账号？",close:{if !store.configuring {logout = false}}) {
                    Text("下次登录请重新输入服务访问令牌。").font(.system(size:14)).padding(.vertical,6)
                } actions:{
                    MobileTextButton(title:"取消") {logout = false}.disabled(store.configuring)
                    MobileTextButton(title:"退出登录") {Task {await store.logout();if !store.loggedIn {logout = false}}}.disabled(store.configuring)
                }
            }
            if connectionInfo {
                MobileDialog(title:"连接状态",close:{connectionInfo = false}) {
                    Text(store.status+"\n\n应用在前台时自动同步。退出后消息保留在服务器，下次打开可继续读取。").font(.system(size:14)).padding(.vertical,6)
                } actions:{MobileTextButton(title:"知道了") {connectionInfo = false}}
            }
            if let error = store.error {
                MobileDialog(title:"暂未完成",close:{store.error = nil}) {
                    Text(error).font(.system(size:14)).padding(.vertical,6)
                } actions:{MobileTextButton(title:"知道了") {store.error = nil}}
            }
        }
    }
    private func showGroup() {guard store.loggedIn else {return};groupNavigation = navigation;group = true}
    private func sync() {store.refresh();store.showNotice("正在同步");Task {await store.refreshDirectory()}}
    private func openRoom(_ room: Conversation) {
        store.select(room.id)
        if let index = path.firstIndex(of:.chat) {path = Array(path.prefix(index+1))} else {path.append(.chat)}
    }
    private func openAgent(_ agent: AgentInfo) {store.navigate(to:agent);if let index = path.firstIndex(of:.chat) {path = Array(path.prefix(index+1))} else {path.append(.chat)}}
}

struct DirectoryRow<Avatar: View>: View {
    let title: String
    let detail: String
    var action: () -> Void
    @ViewBuilder var avatar: Avatar
    var body: some View {
        VStack(spacing:0) {
            Button(action:action) {
                HStack(spacing:0) {
                    avatar.frame(width:48,height:48)
                    VStack(alignment:.leading,spacing:7) {
                        Text(title).font(.system(size:17)).foregroundStyle(MobileStyle.ink)
                        Text(detail).font(.system(size:12)).foregroundStyle(MobileStyle.muted)
                    }.lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(.leading,13)
                    MobileIcon(symbol:.chevron,size:18,color:MobileStyle.color(0xBBBBBB))
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.vertical,13).contentShape(Rectangle())
            }.buttonStyle(MobilePressStyle(radius:0)).frame(maxWidth:.infinity).accessibilityElement(children:.combine)
            MobileDivider(leading:77)
        }.background(.white)
    }
}
struct SettingRow: View {
    let title: String
    var summary = ""
    let symbol: MobileSymbol
    var action: () -> Void
    var body: some View {
        VStack(spacing:0) {
            Button(action:action) {
                HStack(spacing:0) {
                    MobileIcon(symbol:symbol,size:23,color:MobileStyle.color(0x606060))
                    VStack(alignment:.leading,spacing:6) {
                        Text(title).font(.system(size:16)).foregroundStyle(MobileStyle.ink)
                        if !summary.isEmpty {Text(summary).font(.system(size:12)).foregroundStyle(MobileStyle.muted).lineLimit(1)}
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.leading,13)
                    MobileIcon(symbol:.chevron,size:18,color:MobileStyle.color(0xBBBBBB))
                }.padding(.leading,18).padding(.trailing,16).padding(.vertical,16).contentShape(Rectangle())
            }.buttonStyle(MobilePressStyle(radius:0))
            MobileDivider(leading:54)
        }.background(.white)
    }
}

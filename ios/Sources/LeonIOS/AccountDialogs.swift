import SwiftUI

@MainActor
struct LoginView: View {
    @ObservedObject var store: ChatStore
    var close: () -> Void
    @State private var address = ""
    @State private var token = ""
    @State private var name = ""
    var body: some View {
        MobileDialog(title:"注册或登录",close:{if !store.configuring {close()}}) {
            VStack(alignment:.leading,spacing:0) {
                MobileField(label:"UserName") {TextField("UserName",text:$name).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("login_username")}
                MobileField(label:"服务地址") {TextField("HTTPS 服务地址",text:$address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()}
                MobileField(label:"服务访问令牌") {SecureField("服务访问令牌",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled()}
                Text("新用户名会自动注册。App 会记住当前登录状态。").font(.system(size:13)).foregroundStyle(MobileStyle.muted).padding(.top,12).padding(.bottom,12)
                if store.configuring {ProgressView().padding(.vertical,8)}
            }.disabled(store.configuring)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(store.configuring)
            MobileTextButton(title:store.configuring ? "登录中…" : "继续") {Task {if await store.login(address:address,serviceToken:token,username:name) {close()}}}.disabled(store.configuring || token.isEmpty || name.isEmpty)
        }.onAppear {address = store.server}
    }
}
@MainActor
struct GroupForm: View {
    @ObservedObject var store: ChatStore
    var close: () -> Void
    var submit: (String,[String],[String]) async -> Bool
    @State private var name = ""
    @State private var users = ""
    @State private var selected = Set<String>()
    @State private var working = false
    var body: some View {
        MobileDialog(title:"新建群聊",close:{if !working {close()}}) {
            VStack(alignment:.leading,spacing:0) {
                MobileField(label:"群名称") {TextField("群名称",text:$name)}
                MobileField(label:"群成员 UserName（用逗号分隔，可选）") {TextField("UserName",text:$users).textInputAutocapitalization(.never).autocorrectionDisabled()}
                Text("选择加入群聊的 Agent（最多 32 个）").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,18).padding(.bottom,6)
                ForEach(store.agents.filter(\.enabled)) {agent in
                    Button {
                        if selected.contains(agent.id) {selected.remove(agent.id)} else {selected.insert(agent.id)}
                    } label:{
                        HStack(spacing:12) {
                            ZStack {
                                RoundedRectangle(cornerRadius:2).stroke(selected.contains(agent.id) ? MobileStyle.green : MobileStyle.muted,lineWidth:2).frame(width:19,height:19)
                                if selected.contains(agent.id) {Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(MobileStyle.green)}
                            }
                            Text("\(agent.name) @\(agent.handle)").font(.system(size:15)).foregroundStyle(MobileStyle.ink)
                            Spacer(minLength:0)
                        }.padding(.vertical,12).contentShape(Rectangle())
                    }.buttonStyle(MobilePressStyle()).accessibilityAddTraits(selected.contains(agent.id) ? .isSelected : [])
                }
                if working {ProgressView().padding(.vertical,8)}
            }.disabled(working)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(working)
            MobileTextButton(title:"创建") {Task {
                working = true;defer {working = false}
                if await submit(name.trimmingCharacters(in:.whitespacesAndNewlines),Array(selected),usernames(users)) {close()}
            }}.disabled(working || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.utf16.count>60 || selected.count>32 || usernames(users).count>32)
        }
    }
}
func usernames(_ value: String) -> [String] {Array(Set(value.components(separatedBy:CharacterSet(charactersIn:",，")).map {$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter {!$0.isEmpty})).sorted()}

@MainActor
struct NamePrompt: View {
    let title: String
    let note: String
    var initial = ""
    var close: () -> Void
    var submit: (String) async -> Bool
    @State private var name = ""
    @State private var working = false
    var body: some View {
        MobileDialog(title:title,close:{if !working {close()}}) {
            VStack(alignment:.leading,spacing:0) {
                Text(note).font(.system(size:13)).foregroundStyle(MobileStyle.muted).padding(.vertical,6)
                MobileField(label:"对话名称") {TextField("名称",text:$name).accessibilityIdentifier("thread_name")}
                if working {ProgressView().padding(.vertical,12)}
            }.disabled(working)
        } actions:{
            MobileTextButton(title:"取消",action:close).disabled(working)
            MobileTextButton(title:"创建") {Task {working = true;defer {working = false};if await submit(name.trimmingCharacters(in:.whitespacesAndNewlines)) {close()}}}.disabled(working || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.utf16.count>60)
        }.onAppear {
            if initial.isEmpty {let format = DateFormatter();format.dateFormat = "MM-dd HH:mm";name = "新对话 · "+format.string(from:Date())}
            else {name = initial}
        }
    }
}

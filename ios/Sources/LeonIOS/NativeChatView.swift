import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ZipDocument: FileDocument {
    static var readableContentTypes:[UTType] {[.zip]}
    var data:Data
    init(data:Data) {self.data = data}
    init(configuration:ReadConfiguration) throws {guard let bytes = configuration.file.regularFileContents else {throw NativeError(message:"无法读取文件。")};data = bytes}
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {FileWrapper(regularFileWithContents:data)}
}
@MainActor
struct NativeChatView: View {
    enum Panel {
        case photos(ImageOrigin,Int),imageFiles(ImageOrigin),context(String),members(Conversation,Bool),new(AgentInfo,String,ImageOrigin),clear(ClearHistoryPreview),restore(BackupPreview,Data,String?,String,ImageOrigin)
    }
    @ObservedObject var store:ChatStore
    var openRoom:(Conversation)->Void
    var openAgent:(String)->Void
    var openUsage:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var extras = false
    @State private var selection = NSRange(location:0,length:0)
    @State private var composing = false
    @State private var inputHeight:CGFloat = 40
    @State private var candidateIndex = 0
    @State private var dismissedMention = ""
    @State private var panel:Panel?
    @State private var choosingAgent:String?
    @State private var document:ZipDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var importOrigin:ImageOrigin?
    @State private var importAgent:String?
    @State private var sticky = true
    @State private var visible = false
    @State private var firstMessageID:Int64?
    @State private var compactRequests:[String:String] = [:]
    private var token:MentionCompletion.Token? {!composing && store.selected?.direct != true ? MentionCompletion.token(in:store.draft,selection:selection) : nil}
    private var mentionKey:String {"\(store.roomID):\(store.draft):\(selection.location)"}
    private var mentionVisible:Bool {!extras && token != nil && dismissedMention != mentionKey && !store.availableAgents.isEmpty}
    private var candidates:[AgentInfo] {
        guard mentionVisible,let token else {return []}
        return Array(store.availableAgents.filter {MentionCompletion.matches(name:$0.name,handle:$0.handle,query:token.query)}.prefix(8))
    }
    private var statusText:String {store.busy ?? (store.opening.contains(store.roomID) ? "正在打开会话…" : !store.connected ? store.status : "")}
    var body:some View {
        GeometryReader {geometry in
            ScrollViewReader {proxy in
                VStack(spacing:0) {
                    MobileHeader(title:store.selected?.name ?? "聊天",back:back) {chatMenu}
                    if !statusText.isEmpty {Text(statusText).font(.system(size:11)).foregroundStyle(MobileStyle.muted).lineLimit(1).frame(maxWidth:.infinity).padding(.horizontal,12).padding(.vertical,6)}
                    timeline(proxy,width:geometry.size.width-24)
                    composer
                }
            }
        }.background(MobileStyle.bar.ignoresSafeArea()).foregroundStyle(MobileStyle.ink).toolbar(.hidden,for:.navigationBar)
            .overlay {toolDialogs}
            .sheet(isPresented:systemImagePickerPresented) {
                if case .photos(let origin,let limit) = panel {PhotoPicker(store:store,origin:origin,limit:limit)}
                else if case .imageFiles(let origin) = panel {ImageFilePicker(store:store,origin:origin)}
            }
            .fileExporter(isPresented:$exporting,document:document,contentType:.zip,defaultFilename:"Leon-聊天备份-\(Int(Date().timeIntervalSince1970)).zip") {result in
                switch result {
                case .success:store.showNotice("聊天备份已保存，文件包含聊天内容及图片，请妥善保管")
                case .failure(let error):if !isFileCancellation(error) {store.error = error.localizedDescription}
                }
                document = nil
            }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.zip],allowsMultipleSelection:false, onCompletion:importBackup)
            .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) {_ in extras = false}
            .onAppear {visible = true;selection = NSRange(location:(store.draft as NSString).length,length:0);firstMessageID = store.room.messages.first?.id}
            .onDisappear {visible = false}
    }
    private var chatMenu:some View {
        Menu {
            Button("查看 Agent 信息") {
                if store.selected?.direct == true,let id = store.selected?.agentId,!id.isEmpty {showAgentProfile(id)}
                else if store.availableAgents.isEmpty {store.error = "当前会话暂无可查看的 Agent"}
                else {choosingAgent = "profile"}
            }.accessibilityIdentifier("chat_agent_info")
            Button("会话信息") {panel = .members(store.selected ?? Conversation(id:store.roomID,name:"聊天",kind:"group",agentId:nil,agentIds:[]),false)}
            if store.selected?.kind == "group" {Button("群成员") {if let room = store.selected {panel = .members(room,true)}}}
            Button("Token 用量",action:openUsage)
            Button("快捷命令") {hideKeyboard();extras = true}
            Button("新建对话") {chooseAgent(for:"new")}
            Button("立即同步") {store.refresh();store.showNotice("正在同步")}
            if store.selected?.direct != true {Button("提及 Agent") {chooseAgent(for:"mention")}}
        } label:{MobileIcon(symbol:.more).frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel("聊天更多操作")
    }
    private func timeline(_ proxy:ScrollViewProxy,width:CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing:0) {
                if store.room.hasOlder {MobileTextButton(title:store.loadingOlder ? "正在加载…" : "加载更早的消息") {Task {await store.older()}}.disabled(store.loadingOlder).frame(maxWidth:.infinity)}
                if store.room.messages.isEmpty && store.currentPending.isEmpty {
                    VStack(spacing:8) {
                        Text(store.opening.contains(store.roomID) ? "正在打开会话…" : "开始和 \(store.selected?.name ?? "Agent") 聊天").font(.system(size:13)).foregroundStyle(MobileStyle.muted)
                        if store.opening.contains(store.roomID),let agent = store.agent(store.selected?.agentId) {MobileTextButton(title:"重试打开") {Task {await store.open(agent)}}}
                    }.frame(maxWidth:.infinity).padding(.horizontal,16).padding(.top,45).padding(.bottom,35)
                }
                ForEach(ChatTimeline.entries(messages:store.room.messages,jobs:store.visibleJobs,operations:store.room.operations)) {entry in
                    timelineEntry(entry,width:width,resized:{if sticky {DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}})
                }
                ForEach(store.currentPending) {outgoing in
                    MessageBubble(store:store,message:pendingMessage(outgoing),outgoing:outgoing,openAgent:openAgent,availableWidth:width,resized:{if sticky {DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}})
                }
                if store.dismissedCount>0 {MobileTextButton(title:"恢复已忽略的失败提示（\(store.dismissedCount)）") {Task {await store.restoreDismissals()}}.font(.system(size:12))}
                Color.clear.frame(height:1).id("bottom").onAppear {sticky = true}.onDisappear {sticky = false}
            }.padding(.horizontal,12).padding(.top,12).padding(.bottom,18)
        }.background(MobileStyle.chat).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("chat_timeline")
            .onChange(of:store.room.messages.map(\.id)) {_ in
                let next = store.room.messages.first?.id,previous = firstMessageID
                firstMessageID = next
                DispatchQueue.main.async {
                    if let previous,let next,next<previous {proxy.scrollTo("message:\(previous)",anchor:.top)}
                    else if sticky {proxy.scrollTo("bottom",anchor:.bottom)}
                }
            }
            .onChange(of:store.currentPending.map(\.id)) {_ in if sticky {DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}}
            .onChange(of:store.roomID) {_ in
                sticky = true;extras = false;dismissedMention = "";candidateIndex = 0;panel = nil
                firstMessageID = store.room.messages.first?.id;selection = NSRange(location:(store.draft as NSString).length,length:0)
                DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}
            }
    }
    @ViewBuilder private func timelineEntry(_ entry:ChatTimeline.Entry,width:CGFloat,resized:@escaping ()->Void) -> some View {
        switch entry {
        case .time(_,let timestamp):Text(timeLabel(timestamp)).font(.system(size:11)).foregroundStyle(MobileStyle.color(0xAAAAAA)).frame(maxWidth:.infinity).padding(.top,10).padding(.bottom,17)
        case .message(let message):MessageBubble(store:store,message:message,openAgent:openAgent,availableWidth:width,resized:resized)
        case .operation(let operation):Text("\(operation.agentName) · \(operation.progressText)").font(.system(size:12)).foregroundStyle(MobileStyle.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10)
        case .job(let job):jobNotice(job)
        }
    }
    private func jobNotice(_ job:AgentJob) -> some View {
        HStack(spacing:0) {
            Text("\(job.agentName) · \(job.progressText)").font(.system(size:12)).foregroundStyle(MobileStyle.color(0x777777)).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
            if job.failed {
                if job.userId == store.user?.id {
                    MobileTextButton(title:"重试") {Task {_ = await store.tool("正在重试回复…") {try await $0.retryJob(job);return true};store.refresh()}}.frame(width:54,height:48).disabled(store.busy != nil)
                }
                Button {Task {await store.dismiss(job)}} label:{Text("×").font(.system(size:20)).foregroundStyle(MobileStyle.muted).frame(width:48,height:48)}.buttonStyle(MobilePressStyle()).accessibilityLabel("忽略 \(job.agentName) 的失败提示")
            }
        }.padding(.leading,12).padding(.trailing,6).padding(.vertical,3).background(MobileStyle.color(0xE4E4E4),in:RoundedRectangle(cornerRadius:6)).padding(.vertical,7)
    }
    private var composer:some View {
        VStack(spacing:0) {
            MobileDivider()
            if mentionVisible {mentionPanel}
            if !store.draftImages.isEmpty {
                ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {
                    ForEach(store.draftImages) {image in
                        if let picture = UIImage(data:image.data) {
                            Image(uiImage:picture).resizable().scaledToFill().frame(width:64,height:64).clipShape(RoundedRectangle(cornerRadius:6))
                                .overlay(alignment:.topTrailing) {Button {store.removeImage(image.id)} label:{Text("×").font(.system(size:18)).foregroundStyle(.white).frame(width:26,height:26).background(.black.opacity(0.66),in:Circle())}.buttonStyle(.plain).accessibilityLabel("移除图片")}
                        }
                    }
                }.padding(.horizontal,12).padding(.top,6)}
            }
            if store.preparingImages>0 {Text("正在处理图片…").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.top,6)}
            HStack(alignment:.bottom,spacing:0) {
                NativeComposer(text:$store.draft,selection:$selection,composing:$composing,height:$inputHeight,suggestionCount:candidates.count,submit:send,choose:{if !candidates.isEmpty {complete(candidates[candidateIndex % candidates.count])}},move:{step in if !candidates.isEmpty {candidateIndex = (candidateIndex+step+candidates.count)%candidates.count}},dismissSuggestions:{dismissedMention = mentionKey},pasteProvider:{receiveImage(provider:$0,origin:store.imageOrigin,store:store)},beganEditing:{extras = false})
                    .frame(height:inputHeight).disabled(!store.loggedIn)
                Button {hideKeyboard();extras.toggle()} label:{MobileIcon(symbol:.plus).rotationEffect(.degrees(extras ? 45 : 0)).frame(width:40,height:40).contentShape(Rectangle())}.buttonStyle(MobilePressStyle(radius:20)).accessibilityLabel("附件与快捷命令").accessibilityIdentifier("chat_add")
                if !store.draft.isEmpty || !store.draftImages.isEmpty || store.preparingImages>0 {
                    Button(action:send) {Text("发送").font(.system(size:14,weight:.bold)).foregroundStyle(.white).frame(width:58,height:38).background(MobileStyle.green,in:RoundedRectangle(cornerRadius:5))}
                        .buttonStyle(MobilePressStyle()).disabled(!store.canSend || composing).opacity(store.canSend && !composing ? 1 : 0.4).padding(.leading,3).padding(.bottom,1).accessibilityIdentifier("chat_send")
                }
            }.padding(.leading,10).padding(.trailing,8).padding(.vertical,8)
            if store.draft.utf16.count>8000 {Text("消息最多 8,000 字符").font(.system(size:12)).foregroundStyle(.red).padding(.bottom,6)}
            if extras {commandPanel}
        }.background(MobileStyle.bar)
    }
    private var mentionPanel:some View {
        VStack(alignment:.leading,spacing:0) {
            Text("提及 Agent").font(.system(size:12)).foregroundStyle(MobileStyle.muted).padding(.horizontal,6).padding(.vertical,5)
            ScrollView {
                VStack(spacing:0) {
                    if candidates.isEmpty {Text("没有匹配的 Agent").font(.system(size:12)).foregroundStyle(MobileStyle.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,9).padding(.vertical,10)}
                    ForEach(Array(candidates.enumerated()),id:\.element.id) {index,agent in
                        Button {complete(agent)} label:{
                            HStack(spacing:10) {AgentAvatar(store:store,agent:agent,size:32);Text(agent.name).font(.system(size:15));Text("@\(agent.handle)").font(.system(size:11)).foregroundStyle(MobileStyle.muted);Spacer(minLength:0)}.foregroundStyle(MobileStyle.ink).padding(.horizontal,9).padding(.vertical,7).background(index == candidateIndex % max(1,candidates.count) ? MobileStyle.color(0xE2F4E9) : .clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height:132)
        }.padding(.horizontal,10).padding(.vertical,6).background(.white)
    }
    private var commandPanel:some View {
        VStack(spacing:4) {
            HStack(spacing:4) {
                Menu {
                    Button("从相册选择") {panel = .photos(store.imageOrigin,4-store.draftImages.count-store.preparingImages)}
                    Button("从文件选择") {panel = .imageFiles(store.imageOrigin)}
                } label:{MobileToolArtwork(title:"相册",symbol:.photo,accent:0x4778B2,surface:0xEAF1FA)}
                    .disabled(commandsDisabled || store.draftImages.count+store.preparingImages>=4).accessibilityIdentifier("chat_tool_images")
                command("压缩上下文",.compact,0x35896A,0xE7F2EC) {chooseAgent(for:"compact")}
                command("查看上下文",.context,0x35896A,0xE7F2EC) {panel = .context(store.roomID)}
                command("新建对话",.plus,0x35896A,0xE7F2EC) {chooseAgent(for:"new")}
            }
            HStack(spacing:4) {
                command("加载备份",.restore,0x6979A4,0xECEDF6) {importOrigin = store.imageOrigin;importAgent = store.selected?.direct == true ? store.selected?.agentId : nil;importing = true}
                command("清理记录",.clear,0xB56360,0xF8ECEA) {Task {await clear()}}
                command("@ Agent",.agents,0x35896A,0xE7F2EC) {chooseAgent(for:"mention")}.opacity(store.selected?.direct == true ? 0 : 1).disabled(store.selected?.direct == true || store.availableAgents.isEmpty).accessibilityHidden(store.selected?.direct == true)
            }
        }.padding(.horizontal,14).padding(.top,6).padding(.bottom,12).accessibilityIdentifier("chat_extras")
    }
    private func command(_ title:String,_ symbol:MobileSymbol,_ accent:UInt32,_ surface:UInt32,action:@escaping ()->Void) -> some View {
        Button(action:action) {MobileToolArtwork(title:title,symbol:symbol,accent:accent,surface:surface)}
            .buttonStyle(MobilePressStyle(radius:16)).disabled(commandsDisabled)
    }
    private var commandsDisabled:Bool {!store.loggedIn || store.configuring || store.busy != nil || store.savingDraft || store.opening.contains(store.roomID)}
    private var systemImagePickerPresented:Binding<Bool> {
        Binding(get:{switch panel {case .photos,.imageFiles:return true;default:return false}},set:{value in
            if !value {switch panel {case .photos,.imageFiles:panel = nil;default:break}}
        })
    }
    @ViewBuilder private var toolDialogs:some View {
        ZStack {
            if let panel {
                switch panel {
                case .photos,.imageFiles:EmptyView()
                case .context(let room):ContextPanel(store:store,room:room,close:{self.panel = nil})
                case .members(let room,let showMembers):MembersPanel(store:store,room:room,showMembers:showMembers,close:{self.panel = nil})
                case .new(let agent,let request,let origin):NamePrompt(title:"与 \(agent.name) 新建对话",note:"新对话将从空白开始，不携带当前对话的消息和上下文。原对话可从 Agent 主页查看。",close:{self.panel = nil}) {name in
                    guard let result = await store.tool("正在新建对话…",work:{try await $0.newThread(agent:agent.id,name:name,requestId:request)}) else {return false}
                    store.upsert(result);store.showNotice("独立对话已创建");if visible && origin == store.imageOrigin {openRoom(result)};return true
                }
                case .clear(let preview):ClearPanel(store:store,preview:preview,backup:{self.panel = nil;Task {await backup()}},close:{self.panel = nil})
                case .restore(let info,let bytes,let agent,let request,let origin):RestorePanel(store:store,info:info,bytes:bytes,agent:agent,request:request,close:{self.panel = nil}) {result in
                    store.upsert(result);if visible && origin == store.imageOrigin {openRoom(result)}
                }
                }
            }
            if choosingAgent != nil {
                MobileDialog(title:choosingAgent == "profile" ? "查看哪位 Agent" : choosingAgent == "mention" ? "@哪位 Agent" : "选择 Agent",close:{choosingAgent = nil}) {
                    ForEach(store.availableAgents) {agent in
                        Button {let action = choosingAgent ?? "mention";choosingAgent = nil;perform(action,agent:agent)} label:{
                            HStack(spacing:12) {AgentAvatar(store:store,agent:agent,size:40);VStack(alignment:.leading,spacing:3) {Text(agent.name).font(.system(size:15));Text("@\(agent.handle)").font(.system(size:11)).foregroundStyle(MobileStyle.muted)};Spacer(minLength:0)}.foregroundStyle(MobileStyle.ink).padding(.vertical,10).contentShape(Rectangle())
                        }.buttonStyle(MobilePressStyle())
                    }
                } actions:{MobileTextButton(title:"取消") {choosingAgent = nil}}
            }
        }
    }
    private func hideKeyboard() {UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}
    private func showAgentProfile(_ id:String) {hideKeyboard();extras = false;openAgent(id)}
    private func back() {if extras {extras = false} else {hideKeyboard();dismiss()}}
    private func send() {
        guard !composing else {return};let origin = store.imageOrigin
        Task {await store.sendDraft();if origin == store.imageOrigin && store.draft.isEmpty && store.draftImages.isEmpty {extras = false}}
    }
    private func complete(_ agent:AgentInfo) {
        if let token {let result = MentionCompletion.replacing(token,in:store.draft,with:agent.handle);store.draft = result.text;selection = NSRange(location:result.caret,length:0)}
        else {store.draft += (store.draft.isEmpty || store.draft.last?.isWhitespace == true ? "" : " ")+"@\(agent.handle) ";selection = NSRange(location:(store.draft as NSString).length,length:0)}
        dismissedMention = "";candidateIndex = 0
    }
    private func chooseAgent(for command:String) {
        if store.selected?.direct == true,let agent = store.agent(store.selected?.agentId) {perform(command,agent:agent)}
        else if store.availableAgents.isEmpty {store.error = "请先在服务端页面配置并启用 Agent"}
        else {choosingAgent = command}
    }
    private func perform(_ command:String,agent:AgentInfo) {
        switch command {
        case "profile":showAgentProfile(agent.id)
        case "new":panel = .new(agent,UUID().uuidString.lowercased(),store.imageOrigin)
        case "compact":
            let room = store.roomID,key = "\(store.roomID):\(agent.id)",request = compactRequests["\(store.roomID):\(agent.id)"] ?? UUID().uuidString.lowercased()
            compactRequests[key] = request
            Task {if await store.tool("正在提交压缩…",work:{try await $0.compact(room:room,agent:agent.id,requestId:request)}) != nil {compactRequests.removeValue(forKey:key);store.showNotice("已提交上下文压缩，完成后自动显示结果");store.refresh()}}
        default:complete(agent)
        }
    }
    private func clear() async {
        guard store.sending.isEmpty,!store.savingDraft,store.preparingImages == 0 else {store.error = "请等待发送和图片处理完成。";return}
        let origin = store.imageOrigin
        if let preview = await store.tool("正在检查聊天记录…",work:{try await $0.clearPreview(room:origin.room)}),visible,origin == store.imageOrigin {
            if preview.hasActiveWork {store.error = "请等待回复、压缩或总结完成。"} else {panel = .clear(preview)}
        }
    }
    private func backup() async {
        let origin = store.imageOrigin
        if let bytes = await store.tool("正在生成完整备份…",work:{try await $0.backup(room:origin.room)}),visible,origin == store.imageOrigin {document = ZipDocument(data:bytes);exporting = true}
    }
    private func importBackup(_ result:Result<[URL],Error>) {
        guard let origin = importOrigin else {return};let agent = importAgent
        Task {
            do {
                guard let url = try result.get().first else {return}
                let read = try await Task.detached {() throws -> (BackupPreview,Data) in
                    let access = url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
                    let bytes = try LocalFile.read(url,limit:BackupPreview.maximumBytes);return (try BackupPreview(data:bytes),bytes)
                }.value
                guard visible,origin == store.imageOrigin else {return}
                guard agent == nil || read.0.kind == "direct" else {throw NativeError(message:"群聊备份请从群聊入口加载。")}
                panel = .restore(read.0,read.1,agent,UUID().uuidString.lowercased(),origin)
            } catch {if origin.connection == store.connectionID,!isFileCancellation(error) {store.error = error.localizedDescription}}
        }
    }
    private func isFileCancellation(_ error:Error) -> Bool {
        let value = error as NSError
        return error is CancellationError || value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError
    }
    private func timeLabel(_ timestamp:Int64) -> String {
        let date = Date(timeIntervalSince1970:Double(timestamp)/1000)
        return Calendar.current.isDateInToday(date) ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.month().day().hour().minute())
    }
    private func pendingMessage(_ out:Outgoing) -> Message {Message(id:0,clientMessageId:out.id,deviceId:out.deviceId,sender:out.sender,platform:"ios",text:out.text,createdAt:0,conversationId:out.conversationId,role:"user",agentId:nil,replyTo:nil,images:nil,userId:store.user?.id)}
}

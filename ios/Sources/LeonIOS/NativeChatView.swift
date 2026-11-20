import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw NativeError(message:"无法读取文件。") }; self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
@MainActor
struct NativeChatView: View {
    enum Panel: Identifiable {
        case photos(ImageOrigin,Int), context(String), members(Conversation), new(AgentInfo,String,ImageOrigin), clear(ClearHistoryPreview), restore(BackupPreview,Data,String?,String,ImageOrigin)
        var id: String { switch self {case .photos:return "photos";case .context:return "context";case .members:return "members";case .new:return "new";case .clear:return "clear";case .restore:return "restore"} }
    }
    @ObservedObject var store: ChatStore
    var openRoom: (Conversation) -> Void
    var openAgent: (String) -> Void
    var openUsage: () -> Void
    @State private var extras = false
    @State private var selection = NSRange(location:0,length:0)
    @State private var composing = false
    @State private var candidateIndex = 0
    @State private var dismissedMention = ""
    @State private var panel: Panel?
    @State private var choosingAgent: String?
    @State private var document: ZipDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var importOrigin: ImageOrigin?
    @State private var importAgent: String?
    @State private var sticky = true
    @State private var visible = false
    @State private var compactRequests: [String:String] = [:]
    private var token: MentionCompletion.Token? { !composing && store.selected?.direct != true ? MentionCompletion.token(in:store.draft,selection:selection) : nil }
    private var mentionKey: String { "\(store.roomID):\(store.draft):\(selection.location)" }
    private var candidates: [AgentInfo] {
        guard !extras, dismissedMention != mentionKey, let token else { return [] }
        return Array(store.availableAgents.filter {MentionCompletion.matches(name:$0.name,handle:$0.handle,query:token.query)}.prefix(8))
    }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing:0) {
                Text(store.busy ?? store.status).font(.caption2).foregroundStyle(.secondary).padding(6)
                if store.busy != nil { ProgressView().progressViewStyle(.linear) }
                List {
                    if store.room.hasOlder { Button(store.loadingOlder ? "正在加载…" : "加载更早的消息") {Task {await store.older()}}.disabled(store.loadingOlder).frame(maxWidth:.infinity) }
                    if store.opening.contains(store.roomID) { VStack {Text("正在打开私聊…");Button("重试打开") {if let agent = store.agent(store.selected?.agentId) {Task {await store.open(agent)}}} } }
                    ForEach(store.room.messages) {message in
                        MessageBubble(store:store,message:message,openAgent:openAgent,resized:{if sticky {DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}}).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    ForEach(store.currentPending) {outgoing in
                        MessageBubble(store:store,message:pendingMessage(outgoing),outgoing:outgoing,openAgent:openAgent).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    ForEach(store.visibleJobs) {job in
                        HStack {
                            VStack(alignment:.leading) {Text(job.agentName).font(.caption.bold());Text(job.progressText).font(.caption).foregroundStyle(.secondary)}
                            Spacer()
                            if job.failed {
                                if job.userId == store.user?.id {Button {Task {_ = await store.tool("正在重试回复…") {try await $0.retryJob(job);return true};store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("重试回复").disabled(store.busy != nil)}
                                Button {Task {await store.dismiss(job)}} label:{Image(systemName:"xmark")}.accessibilityLabel("忽略失败提示")
                            } else {ProgressView()}
                        }.buttonStyle(.borderless).listRowBackground(Color.gray.opacity(0.12))
                    }
                    ForEach(store.room.operations) {operation in Text("\(operation.agentName) · \(operation.progressText)").font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear) }
                    if store.dismissedCount > 0 {Button("恢复已忽略的失败提示（\(store.dismissedCount)）") {Task {await store.restoreDismissals()}}.font(.caption).listRowBackground(Color.clear)}
                    Color.clear.frame(height:1).id("bottom").listRowSeparator(.hidden).listRowBackground(Color.clear).onAppear {sticky = true}.onDisappear {sticky = false}
                }.listStyle(.plain).scrollContentBackground(.hidden).background(Color(white:0.93)).scrollDismissesKeyboard(.interactively)
                    .overlay {if store.room.loaded && store.room.messages.isEmpty && store.currentPending.isEmpty {Text("开始聊天吧").foregroundStyle(.secondary).allowsHitTesting(false)}}
                    .onChange(of:store.room.messages.map(\.id)) {_ in if sticky {DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}}
                    .onChange(of:store.roomID) {_ in sticky = true;extras = false;selection = NSRange(location:(store.draft as NSString).length,length:0);DispatchQueue.main.async {proxy.scrollTo("bottom",anchor:.bottom)}}
                composer
            }
        }
        .navigationTitle(store.selected?.name ?? "聊天").navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu {
            Button("会话信息") {panel = .members(store.selected ?? Conversation(id:store.roomID,name:"聊天",kind:"group",agentId:nil,agentIds:[]))}
            if store.selected?.kind == "group" {Button("群成员") {if let selected = store.selected {panel = .members(selected)}}}
            Button("Token 用量",action:openUsage)
            Button("立即同步") {store.refresh()}
            Button("备份聊天") {Task {await backup()}}
            Button("新建对话") {chooseAgent(for:"new")}
            if store.selected?.direct != true {Button("提及 Agent") {chooseAgent(for:"mention")}}
        } label:{Image(systemName:"ellipsis.circle")} }
        .sheet(item:$panel) { value in
            switch value {
            case .photos(let origin,let limit): PhotoPicker(store:store,origin:origin,limit:limit)
            case .context(let room): ContextPanel(store:store,room:room)
            case .members(let room): MembersPanel(store:store,room:room)
            case .new(let agent,let request,let origin): NamePrompt(title:"与 \(agent.name) 新建对话",note:"原对话保留，新对话从空白开始。") {name in
                guard let result = await store.tool("正在新建对话…",work:{try await $0.newThread(agent:agent.id,name:name,requestId:request)}) else {return false}
                store.upsert(result); if visible && origin == store.imageOrigin {openRoom(result)};return true
            }
            case .clear(let preview): ClearPanel(store:store,preview:preview,backup:{panel = nil;Task {await backup()}})
            case .restore(let info,let bytes,let agent,let request,let origin): RestorePanel(store:store,info:info,bytes:bytes,agent:agent,request:request) {result in
                store.upsert(result); if visible && origin == store.imageOrigin {openRoom(result)}
            }
            }
        }
        .confirmationDialog("选择 Agent",isPresented:Binding(get:{choosingAgent != nil},set:{if !$0 {choosingAgent = nil}}),titleVisibility:.visible) {
            ForEach(store.availableAgents) {agent in Button(agent.name) {let action = choosingAgent ?? "mention";choosingAgent = nil;perform(action,agent:agent)} }
            Button("取消",role:.cancel) {choosingAgent = nil}
        }
        .fileExporter(isPresented:$exporting,document:document,contentType:.zip,defaultFilename:"Leon-聊天备份-\(Int(Date().timeIntervalSince1970)).zip") {result in if case .failure(let error) = result {store.error = error.localizedDescription};document = nil}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.zip],allowsMultipleSelection:false) {result in
            guard let origin = importOrigin else {return};let agent = importAgent
            Task {
                do {
                    guard let url = try result.get().first else {return}
                    let read = try await Task.detached { () throws -> (BackupPreview,Data) in
                        let access = url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
                        let bytes = try LocalFile.read(url,limit:BackupPreview.maximumBytes)
                        return (try BackupPreview(data:bytes),bytes)
                    }.value
                    guard visible, origin == store.imageOrigin else {return}
                    guard agent == nil || read.0.kind == "direct" else {throw NativeError(message:"群聊备份请从群聊入口加载。")}
                    panel = .restore(read.0,read.1,agent,UUID().uuidString.lowercased(),origin)
                } catch {if origin.connection == store.connectionID {store.error = error.localizedDescription}}
            }
        }
        .onAppear {visible = true;selection = NSRange(location:(store.draft as NSString).length,length:0)}.onDisappear {visible = false}
    }
    private var composer: some View {
        VStack(spacing:5) {
            if !candidates.isEmpty {
                ScrollView {VStack(spacing:0) {ForEach(Array(candidates.enumerated()),id:\.element.id) {index,agent in
                    Button {complete(agent)} label:{HStack {AgentAvatar(store:store,agent:agent,size:28);Text(agent.name);Text("@\(agent.handle)").font(.caption).foregroundStyle(.secondary);Spacer()}.padding(7).background(index == candidateIndex % candidates.count ? Color.green.opacity(0.15) : Color.clear)}.buttonStyle(.plain)
                }}}.frame(maxHeight:145)
            }
            if !store.draftImages.isEmpty {
                ScrollView(.horizontal) {HStack {ForEach(store.draftImages) {image in
                    if let picture = UIImage(data:image.data) {Image(uiImage:picture).resizable().scaledToFill().frame(width:64,height:64).clipped().overlay(alignment:.topTrailing) {Button {store.removeImage(image.id)} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.white,.black)}.accessibilityLabel("移除图片")}}
                }}}.frame(height:70)
            }
            if store.preparingImages > 0 {ProgressView("正在处理图片…").font(.caption)}
            HStack(alignment:.bottom,spacing:6) {
                NativeComposer(text:$store.draft,selection:$selection,composing:$composing,suggestionCount:candidates.count,submit:send,choose:{if !candidates.isEmpty {complete(candidates[candidateIndex % candidates.count])}},move:{step in if !candidates.isEmpty {candidateIndex = (candidateIndex+step+candidates.count)%candidates.count}},dismissSuggestions:{dismissedMention = mentionKey},pasteProvider:{provider in receiveImage(provider:provider,origin:store.imageOrigin,store:store)})
                    .frame(height:min(116,max(44,CGFloat(store.draft.components(separatedBy:"\n").count)*23+20)))
                    .disabled(!store.loggedIn)
                Button {extras.toggle();if extras {UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}} label:{Image(systemName:extras ? "xmark.circle" : "plus.circle").font(.title2)}.accessibilityLabel("快捷命令")
                if !store.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !store.draftImages.isEmpty {Button("发送",action:send).buttonStyle(.borderedProminent).disabled(!store.canSend || composing)}
            }
            if store.draft.utf16.count > 8000 {Text("每条最多 8,000 个 UTF-16 单元").font(.caption).foregroundStyle(.red)}
            if extras {
                ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:85))]) {
                    command("相册","photo") {if store.draftImages.count+store.preparingImages < 4 {panel = .photos(store.imageOrigin,4-store.draftImages.count-store.preparingImages)}}
                    command("压缩上下文","arrow.down.right.and.arrow.up.left") {chooseAgent(for:"compact")}
                    command("查看上下文","text.alignleft") {panel = .context(store.roomID)}
                    command("新建对话","square.and.pencil") {chooseAgent(for:"new")}
                    command("加载备份","folder") {importOrigin = store.imageOrigin;importAgent = store.selected?.direct == true ? store.selected?.agentId : nil;importing = true}
                    command("清理记录","trash") {Task {await clear()}}
                }}.frame(maxHeight:190)
            }
        }.padding(8).background(Color(uiColor:.systemGroupedBackground))
    }
    private func command(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {Button(action:action) {VStack {Image(systemName:symbol).font(.title3);Text(title).font(.caption)}.frame(maxWidth:.infinity).padding(.vertical,8)}.disabled(store.busy != nil || store.savingDraft || store.opening.contains(store.roomID))}
    private func send() {guard !composing else {return};Task {await store.sendDraft()}}
    private func complete(_ agent: AgentInfo) {
        if let token {let result = MentionCompletion.replacing(token,in:store.draft,with:agent.handle);store.draft = result.text;selection = NSRange(location:result.caret,length:0)}
        else {store.draft += " @\(agent.handle) ";selection = NSRange(location:(store.draft as NSString).length,length:0)}
        dismissedMention = "";candidateIndex = 0
    }
    private func chooseAgent(for command: String) {
        if store.selected?.direct == true, let agent = store.agent(store.selected?.agentId) {perform(command,agent:agent)}
        else if store.availableAgents.isEmpty {store.error = "当前会话没有可用 Agent。"}
        else {choosingAgent = command}
    }
    private func perform(_ command: String, agent: AgentInfo) {
        switch command {
        case "new":panel = .new(agent,UUID().uuidString.lowercased(),store.imageOrigin)
        case "compact":
            let room = store.roomID,key = "\(room):\(agent.id)",request = compactRequests["\(room):\(agent.id)"] ?? UUID().uuidString.lowercased()
            compactRequests[key] = request
            Task {if await store.tool("正在提交压缩…",work:{try await $0.compact(room:room,agent:agent.id,requestId:request)}) != nil {compactRequests.removeValue(forKey:key);store.refresh()}}
        default:complete(agent)
        }
    }
    private func clear() async {
        guard store.sending.isEmpty, !store.savingDraft, store.preparingImages == 0 else {store.error = "请等待发送和图片处理完成。";return}
        let origin = store.imageOrigin
        if let preview = await store.tool("正在检查聊天记录…",work:{try await $0.clearPreview(room:origin.room)}), visible, origin == store.imageOrigin {
            if preview.hasActiveWork {store.error = "请等待回复、压缩或总结完成。"} else {panel = .clear(preview)}
        }
    }
    private func backup() async {
        let origin = store.imageOrigin
        if let data = await store.tool("正在生成完整备份…",work:{try await $0.backup(room:origin.room)}), visible, origin == store.imageOrigin {document = ZipDocument(data:data);exporting = true}
    }
    private func pendingMessage(_ out: Outgoing) -> Message {Message(id:0,clientMessageId:out.id,deviceId:out.deviceId,sender:out.sender,platform:"ios",text:out.text,createdAt:0,conversationId:out.conversationId,role:"user",agentId:nil,replyTo:nil,images:nil,userId:store.user?.id)}
}

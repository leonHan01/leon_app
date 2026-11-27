import SwiftUI
import WebKit
import UIKit

@MainActor
struct RichMessageView: UIViewRepresentable {
    let source: String
    let mine: Bool
    @Binding var height: CGFloat
    var resized: () -> Void = {}
    var copied: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator,name:"leonMarkdown")
        let web = WKWebView(frame:.zero,configuration:configuration); web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false; context.coordinator.web = web
        if let url = Bundle.main.url(forResource:"markdown",withExtension:"html",subdirectory:"Markdown") {
            web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
        } else { web.loadHTMLString("<p>正文资源缺失，请重新构建应用。</p>",baseURL:nil) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self; context.coordinator.render()
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName:"leonMarkdown"); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: RichMessageView
        weak var web: WKWebView?
        var ready = false
        private var rendered = ""
        init(_ parent: RichMessageView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
        func render() {
            guard ready, let web,
                  let data = try? JSONSerialization.data(withJSONObject:["source":parent.source,"mine":parent.mine,"dark":false,"platform":"ios"]),
                  let json = String(data:data,encoding:.utf8), json != rendered else { return }
            rendered = json
            web.evaluateJavaScript("void window.renderMessage(\(json));") { [weak self] _,error in
                guard error != nil, let self else { return }
                // Keep original readable text if the renderer fails.
                let text = self.parent.source.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
                self.web?.loadHTMLString("<pre style='white-space:pre-wrap'>\(text)</pre>",baseURL:nil)
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String, text.utf8.count <= 100000,
                  let bytes = text.data(using:.utf8), let event = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  let type = event["type"] as? String else { return }
            switch type {
            case "height":
                guard let value = event["height"] as? Double, value.isFinite else { return }
                let next = CGFloat(min(200000,max(24,value)))
                if abs(parent.height-next) > 1 { parent.height = next; parent.resized() }
            case "copy": if let value = event["text"] as? String {UIPasteboard.general.string = value;parent.copied()}
            case "open": if let value = event["url"] as? String { Self.open(value) }
            case "anchor":
                if let y = event["y"] as? Double, y.isFinite, let web {
                    var ancestor = web.superview
                    while let view = ancestor {
                        if let scroll = view as? UIScrollView {
                            let point = web.convert(CGPoint(x:0,y:max(0,y)),to:scroll)
                            scroll.scrollRectToVisible(CGRect(origin:point,size:CGSize(width:1,height:28)),animated:true);break
                        }
                        ancestor = view.superview
                    }
                }
            default: break
            }
        }
        private static func open(_ value: String) {
            guard let url = URL(string:value), let scheme = url.scheme?.lowercased(), ["https","http","mailto"].contains(scheme) else { return }
            UIApplication.shared.open(url)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL || url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated { Self.open(url.absoluteString) }
            decisionHandler(.cancel)
        }
    }
}
@MainActor
struct AgentAvatar: View {
    @ObservedObject var store: ChatStore
    let agent: AgentInfo?
    var size: CGFloat = 40
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage:image).resizable().scaledToFit() } else { Image(systemName:"person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding(7) } }
            .padding(2).frame(width:size,height:size).background(MobileStyle.color(0xE1F0E8)).clipShape(RoundedRectangle(cornerRadius:7))
            .task(id:"\(store.connectionID):\(agent?.avatarId ?? "alfred"):\(store.connected)") {
                image = nil;let connection = store.connectionID
                if let data = try? await store.avatarData(agent?.avatarId ?? "alfred"),!Task.isCancelled,connection == store.connectionID {
                    image = NativeImageDecoder.image(data,pixels:256,sourceLimit:16000)
                }
            }
    }
}
@MainActor
struct MessagePicture: View {
    @ObservedObject var store: ChatStore
    let id: String
    var maxWidth: CGFloat = 220
    var onQuote:(()->Void)? = nil
    var onFavorite:(()->Void)? = nil
    var onBranch:(()->Void)? = nil
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showing = false
    @State private var branchAfterPreview=false
    @State private var scale: CGFloat = 1
    @State private var previewImage:UIImage?
    @State private var saving = false
    @State private var saveNotice: String?
    @State private var saveDenied = false
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit().padding(3).frame(width:maxWidth,height:maxWidth*0.75).background(.white,in:RoundedRectangle(cornerRadius:6)).onTapGesture { showing = true } }
            else if failed { Button("图片加载失败，点击重试") { attempt += 1 }.font(.caption) }
            else { ProgressView().frame(width:maxWidth,height:maxWidth*0.75) }
        }
        .contextMenu { saveButton;messageActions }
        .alert("保存图片",isPresented:noticePresented(inPreview:false)) { noticeActions } message: { Text(saveNotice ?? "") }
        .task(id:"\(store.connectionID):\(id):\(attempt)") {
            image = nil;failed = false;let connection = store.connectionID
            do {
                let bytes = try await store.imageData(id,retry:attempt > 0)
                guard !Task.isCancelled,connection == store.connectionID else {return}
                image = NativeImageDecoder.image(bytes,pixels:512);failed = image == nil
            } catch {if !Task.isCancelled,connection == store.connectionID {failed = true}}
        }
        .onDisappear {image = nil;previewImage = nil}
        .onChange(of:store.searchConnectionID) {_ in branchAfterPreview=false}
        .sheet(isPresented:$showing,onDismiss:{scale = 1;previewImage = nil;if branchAfterPreview {branchAfterPreview=false;onBranch?()}}) {
            NavigationStack {
                if let image = previewImage ?? image { Image(uiImage:image).resizable().scaledToFit().scaleEffect(scale).gesture(MagnificationGesture().onChanged {scale = min(5,max(1,$0))})
                    .contextMenu { saveButton;messageActions }
                    .toolbar {
                        ToolbarItem(placement:.confirmationAction) { Button("关闭") { showing = false; scale = 1;previewImage = nil } }
                    } }
            }
            .overlay(alignment:.bottomTrailing) { downloadButton.padding(20) }
            .alert("保存图片",isPresented:noticePresented(inPreview:true)) { noticeActions } message: { Text(saveNotice ?? "") }
            .task {
                let connection = store.connectionID
                if let bytes = try? await store.imageData(id),!Task.isCancelled,connection == store.connectionID {previewImage = NativeImageDecoder.image(bytes,pixels:1600)}
            }
        }
    }
    @ViewBuilder private var messageActions:some View {
        if let onQuote {Button {showing=false;onQuote()} label:{Label("引用",systemImage:"quote.bubble")}}
        if let onFavorite {Button {showing=false;onFavorite()} label:{Label("收藏",systemImage:"star")}}
        if let onBranch {Button {if showing {branchAfterPreview=true;showing=false} else {onBranch()}} label:{Label("从这里创建分支",systemImage:"arrow.triangle.branch")}}
    }
    private var saveButton: some View {
        Button { saveImage() } label: { Label(saving ? "保存中…" : "保存图片",systemImage:"square.and.arrow.down") }
            .disabled(saving || (image == nil && previewImage == nil)).accessibilityIdentifier("save_chat_image")
    }
    private var downloadButton: some View {
        Button { saveImage() } label: {
            Group {
                if saving { ProgressView() }
                else { Image(systemName:"arrow.down.to.line").font(.system(size:20,weight:.medium)) }
            }
            .foregroundStyle(.primary).frame(width:48,height:48)
            .background(.regularMaterial,in:Circle())
            .overlay(Circle().stroke(.primary.opacity(0.08),lineWidth:1))
            .shadow(color:.black.opacity(0.15),radius:7,y:3)
        }
        .buttonStyle(.plain).disabled(saving || (image == nil && previewImage == nil))
        .accessibilityLabel(saving ? "正在保存图片" : "下载并保存图片")
        .accessibilityHint("保存到系统相册").accessibilityIdentifier("download_chat_image")
    }
    @ViewBuilder private var noticeActions: some View {
        if saveDenied {
            Button("前往设置") { if let url = URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)} }
        }
        Button("好",role:.cancel) { saveNotice = nil }
    }
    private func noticePresented(inPreview:Bool) -> Binding<Bool> {
        Binding(get:{saveNotice != nil && showing == inPreview},set:{if !$0 {saveNotice = nil}})
    }
    private func saveImage() {
        guard !saving else {return};saving = true;saveDenied = false
        let connection = store.connectionID
        Task {
            defer {saving = false}
            do {
                let data = try await store.imageData(id)
                guard connection == store.connectionID else {return}
                try await PhotoLibrarySaver.save(data)
                if connection == store.connectionID {saveNotice = "已保存到系统相册。"}
            } catch {
                guard connection == store.connectionID else {return}
                saveDenied = (error as? PhotoSaveError) == .permissionDenied
                saveNotice = error.localizedDescription
            }
        }
    }
}
@MainActor
struct PlainMessageText: View {
    let source: String
    let availableWidth: CGFloat
    var fillsWidth = false

    var body: some View {
        let font = UIFont.systemFont(ofSize:14)
        let naturalWidth = ceil((source as NSString).size(withAttributes:[.font:font,.kern:0]).width) + 24
        let width = fillsWidth ? availableWidth : min(availableWidth,max(36,naturalWidth))
        Text(verbatim:source)
            .font(.system(size:14)).kerning(0).foregroundStyle(MobileStyle.ink)
            .textSelection(.enabled)
            .lineSpacing(5).fixedSize(horizontal:false,vertical:true)
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(.horizontal,12).padding(.vertical,12)
            .frame(width:width)
    }
}

@MainActor
struct MessageBubble: View {
    @ObservedObject var store:ChatStore
    let message:Message
    var outgoing:Outgoing? = nil
    var openAgent:(String)->Void
    let availableWidth:CGFloat
    var resized:()->Void = {}
    var actionsEnabled:Bool = true
    @State private var height:CGFloat = 44
    private var mine:Bool {outgoing != nil || store.mine(message)}
    private var agentReply:Bool {message.role == "assistant" && message.agentId != nil}
    private var wide:Bool {!mine && agentReply && message.text.unicodeScalars.count>500}
    private var contentWidth:CGFloat {max(60,availableWidth-(wide ? 0 : 47+(mine || !agentReply ? 44 : 4)))}
    private static let markdownControls = CharacterSet(charactersIn:"\n\r#+*_~`[]()<>\\^=|:$-@&")

    static func usesNativeText(_ source: String) -> Bool {
        // Keep markup, autolinks and HTML whitespace normalization in Markdown.
        guard !source.isEmpty, source.rangeOfCharacter(from:markdownControls) == nil,
              !source.hasPrefix(" "), !source.hasSuffix(" "), !source.contains("  ") else { return false }
        if let dot = source.firstIndex(of:".") {
            // A single trailing period is plain text except for an ordered-list marker.
            guard dot == source.index(before:source.endIndex),
                  !source[..<dot].allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        return !source.unicodeScalars.contains { scalar in
            scalar != " " && (CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.value < 32 || scalar.value == 127 || scalar.value == 0xFEFF)
        }
    }

    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            if wide {
                HStack(spacing:8) {identity;Text(message.sender).font(.system(size:11)).foregroundStyle(MobileStyle.muted)}
                contents
            } else {
                HStack(alignment:.top,spacing:0) {
                    if mine {Color.clear.frame(width:44,height:1)} else {identity}
                    contents.padding(.leading,mine ? 0 : 7)
                    if mine {identity.padding(.leading,7)} else {Color.clear.frame(width:agentReply ? 4 : 44,height:1)}
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,15)
            .contextMenu {
                if !message.text.isEmpty {Button {UIPasteboard.general.string=message.text;store.showNotice("已复制")} label:{Label("复制",systemImage:"doc.on.doc")}}
                if actionsEnabled,outgoing == nil,message.id>0 {
                    Button {store.quoteMessage(message)} label:{Label("引用",systemImage:"quote.bubble")}
                    Button {Task {await store.favoriteMessage(message)}} label:{Label("收藏",systemImage:"star")}
                    Button {store.beginBranch(message)} label:{Label("从这里创建分支",systemImage:"arrow.triangle.branch")}
                }
            }
    }
    private var contents:some View {
        VStack(alignment:mine ? .trailing : .leading,spacing:0) {
            if !mine && !wide && store.selected?.direct != true {
                Text(message.sender).font(.system(size:11)).foregroundStyle(MobileStyle.muted).padding(.leading,5).padding(.bottom,5)
            }
            ForEach(outgoing?.imageIds ?? message.images?.map(\.id) ?? [],id:\.self) {id in
                MessagePicture(store:store,id:id,maxWidth:min(220,contentWidth),onQuote:actionsEnabled && outgoing == nil ? {store.quoteMessage(message)} : nil,onFavorite:actionsEnabled && outgoing == nil ? {Task {await store.favoriteMessage(message)}} : nil,onBranch:actionsEnabled && outgoing == nil ? {store.beginBranch(message)} : nil).padding(.bottom,5)
            }
            ForEach(outgoing?.documents ?? message.documents ?? []){document in DocumentCard(store:store,document:document,message:outgoing==nil && actionsEnabled ? message : nil).padding(.bottom,5)}
            if !message.text.isEmpty {
                let width = max(36,contentWidth-(wide ? 0 : 4))
                Group {
                    if Self.usesNativeText(message.text) {
                        PlainMessageText(source:message.text,availableWidth:width,fillsWidth:wide)
                    } else {
                        RichMessageView(source:message.text,mine:mine,height:$height,resized:resized,copied:{store.showNotice("已复制")})
                            .frame(width:width,height:height)
                    }
                }
                .padding(.leading,!wide && !mine ? 4 : 0).padding(.trailing,!wide && mine ? 4 : 0)
                .background(MobileBubbleShape(mine:mine,wide:wide).fill(mine ? MobileStyle.outgoing : .white))
            }
            if let quote=message.quote,let room=message.conversationId {
                QuoteCard(store:store,quote:quote,room:room,title:store.conversations.first(where:{$0.id==room})?.name ?? "聊天").padding(.top,6)
            }
            if let outgoing {
                Text(store.sending.contains(outgoing.id) ? "发送中…" : "发送未完成").font(.system(size:10)).foregroundStyle(MobileStyle.muted).padding(.leading,5).padding(.top,4)
                if !store.sending.contains(outgoing.id) {MobileTextButton(title:"重试发送") {Task {await store.retry(outgoing)}}}
            }
        }.frame(maxWidth:.infinity,alignment:mine ? .trailing : .leading)
    }
    @ViewBuilder private var identity:some View {
        if mine {
            Text(message.sender.isEmpty ? "我" : String(message.sender.prefix(1))).font(.system(size:16)).foregroundStyle(.white).frame(width:40,height:40).background(MobileStyle.color(0x719983),in:RoundedRectangle(cornerRadius:6))
        } else {
            Button {if agentReply,let id = message.agentId {openAgent(id)}} label:{AgentAvatar(store:store,agent:store.agent(message.agentId))}.buttonStyle(.plain).accessibilityLabel(agentReply ? "查看 \(message.sender) 的详情" : message.sender)
        }
    }
}

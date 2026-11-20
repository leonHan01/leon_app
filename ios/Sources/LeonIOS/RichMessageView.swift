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
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showing = false
    @State private var scale: CGFloat = 1
    @State private var previewImage:UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit().padding(3).frame(width:maxWidth,height:maxWidth*0.75).background(.white,in:RoundedRectangle(cornerRadius:6)).onTapGesture { showing = true } }
            else if failed { Button("图片加载失败，点击重试") { attempt += 1 }.font(.caption) }
            else { ProgressView().frame(width:maxWidth,height:maxWidth*0.75) }
        }
        .task(id:"\(store.connectionID):\(id):\(attempt)") {
            image = nil;failed = false;let connection = store.connectionID
            do {
                let bytes = try await store.imageData(id,retry:attempt > 0)
                guard !Task.isCancelled,connection == store.connectionID else {return}
                image = NativeImageDecoder.image(bytes,pixels:512);failed = image == nil
            } catch {if !Task.isCancelled,connection == store.connectionID {failed = true}}
        }
        .onDisappear {image = nil;previewImage = nil}
        .sheet(isPresented:$showing,onDismiss:{scale = 1;previewImage = nil}) {
            NavigationStack {
                if let image = previewImage ?? image { Image(uiImage:image).resizable().scaledToFit().scaleEffect(scale).gesture(MagnificationGesture().onChanged {scale = min(5,max(1,$0))})
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("关闭") { showing = false; scale = 1;previewImage = nil } } } }
            }
            .task {
                let connection = store.connectionID
                if let bytes = try? await store.imageData(id),!Task.isCancelled,connection == store.connectionID {previewImage = NativeImageDecoder.image(bytes,pixels:1600)}
            }
        }
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
    @State private var height:CGFloat = 44
    private var mine:Bool {outgoing != nil || store.mine(message)}
    private var agentReply:Bool {message.role == "assistant" && message.agentId != nil}
    private var wide:Bool {!mine && agentReply && message.text.unicodeScalars.count>500}
    private var contentWidth:CGFloat {max(60,availableWidth-(wide ? 0 : 47+(mine || !agentReply ? 44 : 4)))}
    private var bubbleWidth:CGFloat {
        // Short plain text wraps tightly; every message still uses the full
        // Markdown parser, so choosing a width cannot drop a syntax feature.
        let controls = CharacterSet(charactersIn:"\n\r#*_~`[]()<>\\^=|!:$-.@&")
        guard !wide,message.text.rangeOfCharacter(from:controls) == nil else {return contentWidth}
        let natural = ceil((message.text as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:14)]).width)+28
        return min(contentWidth,max(40,natural))
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
    }
    private var contents:some View {
        VStack(alignment:mine ? .trailing : .leading,spacing:0) {
            if !mine && !wide && store.selected?.direct != true {
                Text(message.sender).font(.system(size:11)).foregroundStyle(MobileStyle.muted).padding(.leading,5).padding(.bottom,5)
            }
            ForEach(outgoing?.imageIds ?? message.images?.map(\.id) ?? [],id:\.self) {id in
                MessagePicture(store:store,id:id,maxWidth:min(220,contentWidth)).padding(.bottom,5)
            }
            if !message.text.isEmpty {
                RichMessageView(source:message.text,mine:mine,height:$height,resized:resized,copied:{store.showNotice("已复制")})
                    .frame(width:max(36,bubbleWidth-(wide ? 0 : 4)),height:height)
                    .padding(.leading,!wide && !mine ? 4 : 0).padding(.trailing,!wide && mine ? 4 : 0)
                    .background(MobileBubbleShape(mine:mine,wide:wide).fill(mine ? MobileStyle.outgoing : .white))
                    .contextMenu {Button {UIPasteboard.general.string = message.text;store.showNotice("已复制")} label:{Label("复制原文",systemImage:"doc.on.doc")}}
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

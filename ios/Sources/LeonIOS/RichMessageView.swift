import SwiftUI
import WebKit
import UIKit

@MainActor
struct RichMessageView: UIViewRepresentable {
    let source: String
    let mine: Bool
    @Binding var height: CGFloat
    var resized: () -> Void = {}
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
            case "copy": UIPasteboard.general.string = event["text"] as? String
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
            .frame(width:size,height:size).background(Color.green.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius:8))
            .task(id:"\(store.connectionID):\(agent?.avatarId ?? "alfred"):\(store.connected)") {
                image = nil
                if let data = try? await store.avatarData(agent?.avatarId ?? "alfred") { image = UIImage(data:data) }
            }
    }
}
@MainActor
struct MessagePicture: View {
    @ObservedObject var store: ChatStore
    let id: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showing = false
    @State private var scale: CGFloat = 1
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:230,maxHeight:190).onTapGesture { showing = true } }
            else if failed { Button("图片加载失败，点击重试") { attempt += 1 }.font(.caption) }
            else { ProgressView().frame(width:160,height:90) }
        }
        .task(id:"\(store.connectionID):\(id):\(attempt)") {
            failed = false
            do { let bytes = try await store.imageData(id,retry:attempt > 0); image = UIImage(data:bytes); failed = image == nil }
            catch { failed = true }
        }
        .sheet(isPresented:$showing) {
            NavigationStack {
                if let image { Image(uiImage:image).resizable().scaledToFit().scaleEffect(scale).gesture(MagnificationGesture().onChanged {scale = min(5,max(1,$0))})
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("关闭") { showing = false; scale = 1 } } } }
            }
        }
    }
}
@MainActor
struct MessageBubble: View {
    @ObservedObject var store: ChatStore
    let message: Message
    var outgoing: Outgoing? = nil
    var openAgent: (String) -> Void
    var resized: () -> Void = {}
    @State private var height: CGFloat = 64
    private var mine: Bool { outgoing != nil || store.mine(message) }
    private var wide: Bool { !mine && message.agentId != nil && message.text.unicodeScalars.count > 500 }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            if wide { HStack { identity; Text(message.sender).font(.caption).foregroundStyle(.secondary) } }
            HStack(alignment:.top,spacing:8) {
                if !mine && !wide { identity }
                if mine { Spacer(minLength:30) }
                VStack(alignment:mine ? .trailing : .leading,spacing:6) {
                    if !mine && !wide && store.selected?.direct != true { Text(message.sender).font(.caption).foregroundStyle(.secondary) }
                    ForEach(outgoing?.imageIds ?? message.images?.map(\.id) ?? [],id:\.self) { id in MessagePicture(store:store,id:id) }
                    if !message.text.isEmpty {
                        RichMessageView(source:message.text,mine:mine,height:$height,resized:resized)
                            .frame(height:height).background(mine ? Color(red:0.7,green:0.92,blue:0.56) : .white).clipShape(RoundedRectangle(cornerRadius:7))
                            .contextMenu { Button { UIPasteboard.general.string = message.text } label: {Label("复制原文",systemImage:"doc.on.doc")} }
                    }
                    if let outgoing {
                        Button(store.sending.contains(outgoing.id) ? "正在发送…" : "重试发送") { Task { await store.retry(outgoing) } }
                            .font(.caption).disabled(store.sending.contains(outgoing.id))
                    } else { Text(message.date,style:.time).font(.caption2).foregroundStyle(.secondary) }
                }
                if !mine && !wide { Spacer(minLength:message.agentId == nil ? 30 : 0) }
                if mine { identity }
            }
        }.padding(.vertical,6)
    }
    @ViewBuilder private var identity: some View {
        if mine { Text(String(message.sender.prefix(1))).foregroundStyle(.white).frame(width:40,height:40).background(Color.green.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius:8)) }
        else { Button { if let id = message.agentId { openAgent(id) } } label: { AgentAvatar(store:store,agent:store.agent(message.agentId)) }.buttonStyle(.plain) }
    }
}

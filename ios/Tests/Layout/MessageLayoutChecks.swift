import SwiftUI
import UIKit
import WebKit

// Host the production bubble without login, network, simulator or game.
@main
final class MessageLayoutChecks: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Message layout", sessionRole: session.role)
        configuration.delegateClass = MessageLayoutScene.self
        return configuration
    }
}

final class MessageLayoutScene: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        Task { @MainActor in await run() }
    }

    @MainActor private func run() async {
        guard let root = window?.rootViewController else { exit(2) }
        let store = ChatStore(disk: FilePersistence(root: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)), credentials: MessageLayoutCredentials())
        store.user = ChatUser(id: "layout-user", username: "Layout")
        var failures: [String] = []
        let samples = ["已生成图片。", "已生成图片！", "你好，世界。", "可以吗？", "好的，谢谢！", "你好", "你好我是你的助手", "这是一条普通的中文回复", "测试最后一个字是否换行", "Hello world", "Hello world!", "Hello world.", "中英混排 Hello 世界", "你好🙂"]
        var scenarios = samples.map { (name: "assistant", text: $0, expected: $0, width: CGFloat(393), native: true) }
        for (source,expected) in [("+ 你好","你好"),("+ 已生成图片。","已生成图片。"),("  + 你好","你好"),
                                   ("**粗体**","粗体"),("example.com","example.com"),("a@example.com","a@example.com")] {
            scenarios.append((name:"assistant",text:source,expected:expected,width:393,native:false))
        }
        for source in ["# 标题","$x^2$","1. 列表","两行\n正文","两个  空格","&#65;","`行内代码`","***","https://example.com"] {
            if MessageBubble.usesNativeText(source) { failures.append("Markdown content sent to native text: \(source)") }
        }
        for width: CGFloat in [320, 393, 430] {
            for name in ["received", "sent", "pending", "history"] {
                scenarios.append((name: name, text: "已生成图片。", expected:"已生成图片。", width: width, native:true))
                scenarios.append((name: name, text: "**你好**", expected:"你好", width: width, native:false))
            }
        }
        for (index, scenario) in scenarios.enumerated() {
            let (name, text, expected, screenWidth, native) = scenario
            let assistant = name == "assistant" || name == "history"
            let mine = name == "sent" || name == "pending"
            let message = Message(id: Int64(index + 1), clientMessageId: "layout-\(index)", deviceId: mine ? "local" : "remote", sender: assistant ? "AI" : "User", platform: assistant ? "agent" : "ios", text: text, createdAt: 1000, conversationId: "shared", role: assistant ? "assistant" : "user", agentId: assistant ? "fixture" : nil, replyTo: nil, images: nil, userId: mine ? "layout-user" : "other-user")
            let outgoing = name == "pending" ? Outgoing(clientMessageId: message.clientMessageId, deviceId: message.deviceId, sender: message.sender, platform: "ios", text: text, conversationId: "shared") : nil
            let width = screenWidth - 24
            let label = "\(name) \(Int(screenWidth)) \(text)"
            let host = UIHostingController(rootView: MessageBubble(store: store, message: message, outgoing: outgoing, openAgent: { _ in }, availableWidth: width, actionsEnabled: name != "history"))
            root.addChild(host)
            root.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            host.didMove(toParent: root)
            if native {
                host.view.layoutIfNeeded()
                if !MessageBubble.usesNativeText(text) || descendants(host.view).contains(where: { $0 is WKWebView }) {
                    failures.append("\(label): short plain text created a WebView")
                }
                let textHost = UIHostingController(rootView:PlainMessageText(source:text,availableWidth:width-95))
                let size = textHost.sizeThatFits(in:CGSize(width:width,height:600))
                if size.height < 35 || size.height > 50 || size.width > width {
                    failures.append("\(label): one-line native text has unexpected size \(size)")
                }
            } else {
                do {
                    let web = try await waitForWeb(in: host.view)
                    let metrics = try await web.evaluateJavaScript("""
                    (() => {
                        const p = document.querySelector('#message p, #message li');
                        const range = document.createRange(); range.selectNodeContents(p);
                        const lines = [...new Set([...range.getClientRects()].map(r => Math.round(r.top)))];
                        const span = document.createElement('span');
                        span.style.whiteSpace = 'nowrap'; span.textContent = p.textContent;
                        p.append(span); const natural = span.getBoundingClientRect().width; span.remove();
                        return {lines: lines.length, natural, width: p.getBoundingClientRect().width, text: p.textContent,
                                link: p.querySelector('a')?.href ?? '', bold: !!p.querySelector('strong')};
                    })()
                    """) as? [String: Any] ?? [:]
                    let lines = metrics["lines"] as? Int ?? 0
                    print("\(label): web=\(web.bounds.width), \(metrics)")
                    if lines != 1 { failures.append("\(label): short message wraps to \(lines) lines") }
                    if metrics["text"] as? String != expected { failures.append("\(label): message text changed") }
                    if text == "example.com", metrics["link"] as? String != "http://example.com/" { failures.append("\(label): automatic link missing") }
                    if text == "a@example.com", metrics["link"] as? String != "mailto:a@example.com" { failures.append("\(label): automatic email link missing") }
                    if text.hasPrefix("**"), metrics["bold"] as? Bool != true { failures.append("\(label): bold formatting missing") }
                    if web.convert(web.bounds, to: host.view).maxX > width + 0.5 { failures.append("\(label): message exceeds the row width") }
                    let outgoingStyle = try await web.evaluateJavaScript("document.body.dataset.mine === 'true'") as? Bool
                    if outgoingStyle != mine { failures.append("\(label): wrong incoming/outgoing test fixture") }
                } catch { failures.append("\(label): \(error)") }
            }
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:1600,height:1600))
        let data=renderer.jpegData(withCompressionQuality:0.8) {context in UIColor.red.setFill();context.fill(CGRect(x:0,y:0,width:1600,height:1600))}
        let imageState=CollectionImageState()
        await imageState.load(pixels:512) {data}
        if imageState.image?.cgImage?.width != 512 || imageState.image?.cgImage?.height != 512 {failures.append("favorite preview decoded at the wrong resolution")}
        imageState.release()
        if imageState.image != nil {failures.append("offscreen favorite kept its decoded image")}
        var release:CheckedContinuation<Data,Never>?
        let loading=Task {await imageState.load(pixels:512) {await withCheckedContinuation {release=$0}}}
        while release==nil {await Task.yield()}
        imageState.release();release!.resume(returning:data);await loading.value
        if imageState.image != nil || imageState.failed {failures.append("late favorite load repopulated an offscreen image")}
        await imageState.load(pixels:512) {Data([0])}
        if !imageState.failed {failures.append("invalid favorite image has no retry state")}
        await imageState.load(pixels:512) {data}
        if imageState.failed || imageState.image == nil {failures.append("favorite image retry did not recover")}
        imageState.release()
        let report = failures.map { "FAIL: " + $0 }.joined(separator: "\n") + "\n" + (failures.isEmpty ? "PASS: \(scenarios.count) production message layout scenarios and 4 favorite image lifecycle checks" : "FAIL: \(failures.count) layout/image assertions") + "\n"
        if let path = ProcessInfo.processInfo.environment["LEON_LAYOUT_RESULT"] { try? report.write(toFile: path, atomically: true, encoding: .utf8) }
        print(report)
        exit(failures.isEmpty ? 0 : 1)
    }

    @MainActor private func waitForWeb(in view: UIView) async throws -> WKWebView {
        for _ in 0..<200 {
            view.setNeedsLayout(); view.layoutIfNeeded()
            if let web = descendants(view).compactMap({ $0 as? WKWebView }).first,
               (try? await web.evaluateJavaScript("!!document.querySelector('#message p, #message li') && !!document.querySelector('#message').textContent.trim()")) as? Bool == true {
                return web
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw NSError(domain: "MessageLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Message renderer did not load"])
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

private actor MessageLayoutCredentials: CredentialStorage {
    func read() -> Credentials? { nil }
    func save(_ credentials: Credentials?) {}
}

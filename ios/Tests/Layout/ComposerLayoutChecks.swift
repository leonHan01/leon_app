import SwiftUI
import UIKit

// A Catalyst-only harness: real UIKit/SwiftUI layout, no login, network or game.
// It hosts the production chat at phone widths, without changing the Mac app.
@main
final class ComposerLayoutChecks: UIResponder, UIApplicationDelegate {
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name:"Layout",sessionRole:session.role)
        config.delegateClass = ComposerLayoutScene.self
        return config
    }
}
final class ComposerLayoutScene:NSObject,UIWindowSceneDelegate {
    var window:UIWindow?
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {return}
        let window = UIWindow(windowScene:scene)
        window.rootViewController = UIViewController();window.makeKeyAndVisible();self.window = window
        Task { @MainActor in await run() }
    }
    @MainActor private func run() async {
        guard let root = window?.rootViewController else {exit(2)}
        let store = ChatStore(disk:FilePersistence(root:URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)),credentials:LayoutCredentials())
        await store.initialize()
        let host = UIHostingController(rootView:NativeChatView(store:store,openRoom:{_ in},openAgent:{_ in},openUsage:{}))
        root.addChild(host);root.view.addSubview(host.view);host.didMove(toParent:root)
        var failures:[String] = [],results:[String] = []
        let samples = [("short","你好"),("typed",String(repeating:"逐字输入检查自动换行。",count:20)),("Chinese",String(repeating:"这是一段用于检查输入框自动换行的中文。",count:100)),("English",String(repeating:"unbrokenword",count:180)),("URL","https://example.com/"+String(repeating:"abcdefghij",count:220)),("newlines",String(repeating:"第一行\n第二行\n",count:80))]
        for width:CGFloat in [320,393,430] {
            host.view.frame = CGRect(x:0,y:0,width:width,height:800)
            for (name,text) in samples {
                store.draft = ""
                try? await Task.sleep(nanoseconds:150_000_000)
                guard let editor = descendants(host.view).compactMap({$0 as? ComposerTextView}).first else {failures.append("missing editor");continue}
                // Exercise native insertion/paste, not just binding restoration.
                if name == "typed" {
                    editor.becomeFirstResponder()
                    for character in text {
                        editor.insertText(String(character))
                        try? await Task.sleep(nanoseconds:5_000_000)
                        let frame = editor.convert(editor.bounds,to:host.view)
                        if frame.maxX > width-109+0.5 {failures.append("\(Int(width)) typed: send crowded out at \(editor.text.count) characters, editor \(frame)");break}
                    }
                } else {editor.insertText(text)}
                try? await Task.sleep(nanoseconds:150_000_000)
                host.view.setNeedsLayout();host.view.layoutIfNeeded()
                try? await Task.sleep(nanoseconds:150_000_000)
                guard let input = descendants(host.view).compactMap({$0 as? ComposerTextView}).first else {failures.append("missing editor");continue}
                if store.draft != text {failures.append("\(Int(width)) \(name): input delegate lost text")}
                let frame = input.convert(input.bounds,to:host.view)
                let maximum = (input.font?.lineHeight ?? 20)*4+20
                let ideal = input.sizeThatFits(CGSize(width:input.bounds.width,height:.greatestFiniteMagnitude)).height
                // Reserve 40pt for attachments, 58+3pt for send, and 8pt trailing.
                if frame.minX < 9 || frame.maxX > width-109+0.5 {failures.append("\(Int(width)) \(name): editor \(frame) leaves no room for send")}
                if name != "short" && (ideal<=40 || input.bounds.height<=40) {failures.append("\(Int(width)) \(name): long text did not wrap/grow (ideal \(ideal), frame \(frame))")}
                if input.bounds.height > maximum+1 {failures.append("\(Int(width)) \(name): editor grew beyond four lines")}
                if name != "short" && !input.isScrollEnabled {failures.append("\(Int(width)) \(name): long text cannot scroll")}
                if name == "short" && (input.bounds.height>41 || input.isScrollEnabled) {failures.append("\(Int(width)): short text did not reset")}
                results.append("\(Int(width)) \(name): width=\(Int(frame.width)), height=\(Int(frame.height)), ideal=\(Int(ideal)), scroll=\(input.isScrollEnabled)")
            }
        }
        let report = (results+failures.map {"FAIL: "+$0}+[failures.isEmpty ? "PASS: 18 production composer layout scenarios" : "FAIL: \(failures.count) layout assertions"]).joined(separator:"\n")+"\n"
        if let path = ProcessInfo.processInfo.environment["LEON_LAYOUT_RESULT"] {try? report.write(toFile:path,atomically:true,encoding:.utf8)}
        print(report);exit(failures.isEmpty ? 0 : 1)
    }
    private func descendants(_ view:UIView) -> [UIView] { [view]+view.subviews.flatMap(descendants) }
}
private actor LayoutCredentials: CredentialStorage {
    func read() -> Credentials? {Credentials(server:"https://example.invalid",user:ChatUser(id:"layout-fixture",username:"layout-fixture"),token:"layout-fixture")}
    func save(_ credentials:Credentials?) {}
}

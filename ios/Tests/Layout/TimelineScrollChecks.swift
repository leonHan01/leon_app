import SwiftUI
import UIKit

@main
final class TimelineScrollChecks:UIResponder,UIApplicationDelegate {
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
        let configuration=UISceneConfiguration(name:"Timeline scrolling",sessionRole:session.role);configuration.delegateClass=TimelineScrollScene.self;return configuration
    }
}
final class TimelineScrollScene:NSObject,UIWindowSceneDelegate {
    var window:UIWindow?
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions){
        guard let scene=scene as? UIWindowScene else {return};let window=UIWindow(windowScene:scene);window.rootViewController=UIViewController();window.makeKeyAndVisible();self.window=window
        Task {@MainActor in await run()}
    }
    @MainActor private func run() async {
        guard let root=window?.rootViewController else {exit(2)}
        let store=ChatStore(disk:FilePersistence(root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),credentials:ScrollCheckCredentials())
        store.conversations=[Conversation(id:"room:a",name:"缓存会话",kind:"direct",agentId:nil,agentIds:[]),Conversation(id:"room:b",name:"延迟加载",kind:"direct",agentId:nil,agentIds:[])]
        store.roomID="room:a";store.room.messages=messages(10,count:40,room:"room:a");store.room.loaded=true
        var failures:[String]=[]
        var viewport=ConversationViewport()
        func host()->UIHostingController<NativeChatView>{
            let host=UIHostingController(rootView:NativeChatView(store:store,openRoom:{_ in},openAgent:{_ in},openUsage:{},viewport:viewport));root.addChild(host);root.view.addSubview(host.view);host.view.frame=CGRect(x:0,y:0,width:393,height:756);host.didMove(toParent:root);return host
        }
        var controller=host()
        func settle() async {
            var previous:[CGFloat]=[],stable=0
            for tick in 0..<200 {
                root.view.layoutIfNeeded();try? await Task.sleep(nanoseconds:20_000_000)
                let metrics=descendants(controller.view).compactMap {$0 as? UIScrollView}.filter {$0.isScrollEnabled && !($0 is UITextView)}.flatMap {[$0.contentSize.height,$0.contentOffset.y]}
                stable=metrics==previous ? stable+1 : 0;previous=metrics
                if tick>=35 && stable>=20 {break}
            }
        }
        func check(_ label:String){
            let candidates=descendants(controller.view).compactMap {$0 as? UIScrollView}.filter {!($0 is UITextView)&&$0.isScrollEnabled&&$0.bounds.height>100}
            guard let scroll=candidates.max(by:{$0.contentSize.height-$0.bounds.height<$1.contentSize.height-$1.bounds.height}) else {failures.append(label+": timeline scroll view missing");return}
            let remaining=scroll.contentSize.height-scroll.bounds.height+scroll.adjustedContentInset.bottom-scroll.contentOffset.y
            if remaining>48 {failures.append("\(label): \(Int(remaining))pt from latest; offset=\(Int(scroll.contentOffset.y)), content=\(Int(scroll.contentSize.height))")}
        }
        await settle();check("cached history on first entry")
        if let last=store.room.messages.last {
            store.room.messages[store.room.messages.count-1]=message(last.id,room:"room:a",text:String(repeating:"内容稍后完成排版，最新消息仍应保持可见。",count:90))
        }
        await settle();check("same message ID after delayed height expansion")
        func timeline()->UIScrollView? {descendants(controller.view).compactMap {$0 as? UIScrollView}.filter {!($0 is UITextView)&&$0.isScrollEnabled&&$0.bounds.height>100}.max(by:{$0.contentSize.height<$1.contentSize.height})}
        viewport.handle.began?();viewport.proxy?.scrollTo("message:20",anchor:.top)
        await settle()
        if let scroll=timeline(){scroll.setContentOffset(CGPoint(x:0,y:scroll.contentOffset.y+25),animated:false)}
        await settle();viewport.handle.ended?()
        await settle()
        let saved=store.scrollPositions["room:a"]
        if saved?.messageID==nil {failures.append("reading position has no visible message anchor")}
        if let scroll=timeline(),scroll.contentSize.height-scroll.bounds.height-scroll.contentOffset.y<200 {failures.append("reading fixture must be away from the latest message")}
        func checkRestored(_ label:String){
            guard let saved,let actual=viewport.currentPosition else {failures.append(label+": missing saved position");return}
            if saved.messageID != actual.messageID || abs(saved.messageTop-actual.messageTop)>2 {failures.append("\(label): anchor \(String(describing:actual.messageID)) at \(actual.messageTop), expected \(String(describing:saved.messageID)) at \(saved.messageTop)")}
        }
        store.room.messages.append(message(1000,room:"room:a",text:"阅读旧消息时收到的新回复"));await settle();checkRestored("new reply does not interrupt reading history")
        store.room.messages[0]=message(10,room:"room:a",text:String(repeating:"较早消息稍后完成排版，当前阅读位置应保持。",count:100))
        await settle();checkRestored("height expansion above the reading anchor")
        viewport.loadOlder()
        store.room.messages.insert(message(1,room:"room:a",text:"更早的历史消息"),at:0)
        await settle();checkRestored("loading an older page preserves the reading anchor")
        store.select("room:b");await settle()
        store.room.messages=messages(100,count:35,room:"room:b");store.room.loaded=true
        await settle();check("history arriving after entering an empty room")
        store.select("room:a");await settle();checkRestored("switching back to cached history")
        controller.willMove(toParent:nil);controller.view.removeFromSuperview();controller.removeFromParent();viewport=ConversationViewport();controller=host()
        await settle();checkRestored("returning from another page without new IDs")
        let report=failures.map {"FAIL: "+$0}.joined(separator:"\n")+"\n"+(failures.isEmpty ? "PASS: 8 production conversation scrolling scenarios" : "FAIL: \(failures.count) conversation scrolling scenarios")+"\n"
        if let path=ProcessInfo.processInfo.environment["LEON_SCROLL_RESULT"] {try? report.write(toFile:path,atomically:true,encoding:.utf8)}
        print(report);exit(failures.isEmpty ? 0 : 1)
    }
    private func message(_ id:Int64,room:String,text:String)->Message {Message(id:id,clientMessageId:"scroll-\(id)",deviceId:"other",sender:"助手",platform:"ios",text:text,createdAt:id*1000,conversationId:room,role:"user",agentId:nil,replyTo:nil,images:[],userId:nil)}
    private func messages(_ first:Int64,count:Int,room:String)->[Message]{(0..<count).map {message(first+Int64($0),room:room,text:"第 \($0) 条："+String(repeating:"进入会话应显示最新消息。",count:8))}}
    private func descendants(_ view:UIView)->[UIView]{[view]+view.subviews.flatMap(descendants)}
}
private actor ScrollCheckCredentials:CredentialStorage {
    func read()->Credentials? {nil}
    func save(_ credentials:Credentials?){}
}

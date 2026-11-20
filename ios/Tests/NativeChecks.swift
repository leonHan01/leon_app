import Foundation

actor MemoryDisk: Persistence {
    var snapshots: [String:OutboxSnapshot] = [:]
    var pictures: [String:Data] = [:]
    var fail = false
    func setFail(_ value: Bool) {fail = value}
    func deviceID() -> String {"00000000-0000-4000-8000-000000000001"}
    func load(scope: String) -> OutboxSnapshot {snapshots[scope] ?? OutboxSnapshot()}
    func save(scope: String,snapshot: OutboxSnapshot) throws {if fail {throw NativeError(message:"disk full")};snapshots[scope] = snapshot}
    func saveImage(_ image: DraftImage,scope: String) {pictures[scope+image.id] = image.data}
    func image(_ id: String,scope: String) -> Data? {pictures[scope+id]}
    func removeImages(_ ids: [String],scope: String) {ids.forEach {pictures.removeValue(forKey:scope+$0)}}
    func imageCount() -> Int {pictures.count}
}
actor MemoryCredentials: CredentialStorage {
    var value: Credentials?
    init(_ value: Credentials? = Credentials(server:"https://example.test",user:ChatUser(id:"user-1",username:"Alice"),token:"chat_test")) {self.value = value}
    func read() -> Credentials? {value}
    func save(_ value: Credentials?) {self.value = value}
}
final class FakeAPI: ChatAPI, @unchecked Sendable {
    var branchHook:((String,Int64,String,String) async throws -> Conversation)?
    var conversationsHook: (() async throws -> [Conversation])?
    var favoriteImageHook: ((Int64,String) async throws -> Data)?
    var searchHook: ((String,String?,Int64?) async throws -> ChatSearchPage)?
    var sendHook: ((Outgoing) async throws -> Message)?
    var directHook: ((String) async throws -> Conversation)?
    var usageHook: (() async throws -> [ModelUsage])?
    var imageHook: ((String) async throws -> Data)?
    var avatarHook: ((String) async throws -> Data)?
    var sends: [Outgoing] = [];var uploads: [String] = [];var logouts = 0
    func login(_ username: String) async throws -> LoginResult {LoginResult(user:ChatUser(id:"user-1",username:username),sessionToken:"chat_new")}
    func logout() async throws {logouts += 1}
    func agents() async throws -> [AgentInfo] {[]}
    func conversations() async throws -> [Conversation] {if let conversationsHook {return try await conversationsHook()};return []}
    func heartbeat(deviceId: String,name: String) async throws {}
    func page(room: String,after: Int64?,before: Int64?) async throws -> MessagePage {pageFixture([])}
    func search(query: String,room: String?,before: Int64?) async throws -> ChatSearchPage {if let searchHook {return try await searchHook(query,room,before)};return ChatSearchPage(results:[],hasMore:false,nextBefore:nil)}
    func searchContext(room: String,message: Int64,direction: String) async throws -> ChatSearchContext {ChatSearchContext(messages:[],hasOlder:false,hasNewer:false,historyRevision:1)}

    func direct(_ agent: String) async throws -> Conversation {if let directHook {return try await directHook(agent)};return Conversation(id:"dm:user-1:\(agent)",name:"A",kind:"direct",agentId:agent,agentIds:[agent])}
    func newThread(agent: String,name: String,requestId: String) async throws -> Conversation {Conversation(id:"thread:\(requestId)",name:name,kind:"direct",agentId:agent,agentIds:[agent])}
    func branch(room:String,message:Int64,name:String,requestId:String) async throws -> Conversation {guard let branchHook else {throw NativeError(message:"unused branch")};return try await branchHook(room,message,name,requestId)}
    func group(name: String,agentIds: [String],usernames: [String]) async throws -> Conversation {Conversation(id:"group:1",name:name,kind:"group",agentId:nil,agentIds:agentIds)}
    func members(room: String,adding: [String]?) async throws -> [ChatUser] {[]}
    func addAgents(room:String,agentIds:[String]) async throws -> Conversation {Conversation(id:room,name:"群聊",kind:"group",agentId:nil,agentIds:agentIds)}
    func send(_ message: Outgoing) async throws -> Message {sends.append(message);if let sendHook {return try await sendHook(message)};return messageFixture(3,client:message.id,device:message.deviceId)}
    func retryJob(_ job: AgentJob) async throws {}
    func addFavorite(_ message:Int64) async throws -> FavoriteItem {FavoriteItem(id:1,message:messageFixture(message),conversationName:"测试",savedAt:1)}
    func favorites(query:String,before:Int64?) async throws -> FavoritePage {FavoritePage(results:[],hasMore:false,nextBefore:nil)}
    func removeFavorite(_ id:Int64) async throws {}
    func favoriteImage(_ favorite:Int64,image:String) async throws -> Data {if let favoriteImageHook {return try await favoriteImageHook(favorite,image)};return Data()}

    func uploadImage(id: String,room: String,data: Data) async throws {uploads.append(id)}
    func image(_ id: String) async throws -> Data {if let imageHook {return try await imageHook(id)};return Data([1,2,3])}
    func avatar(_ id: String) async throws -> Data {if let avatarHook {return try await avatarHook(id)};return Data([1,2,3])}
    func usage() async throws -> [ModelUsage] {if let usageHook {return try await usageHook()};return []}
    func context(room: String) async throws -> ConversationContext {ConversationContext(conversationId:room,recentRounds:10,inputTokenBudget:32000,topicStartedAfter:0,agents:[])}
    func configureContext(room: String,rounds: Int) async throws -> ConversationContext {try await context(room:room)}
    func compact(room: String,agent: String,requestId: String) async throws -> ContextOperation {throw NativeError(message:"unused")}
    func clearPreview(room: String) async throws -> ClearHistoryPreview {ClearHistoryPreview(conversationId:room,conversationName:"测试",messageCount:1,latestMessageId:3,historyRevision:1,hasActiveWork:false)}
    func clear(_ preview: ClearHistoryPreview,requestId: String) async throws -> ClearHistoryResult {ClearHistoryResult(clearedMessages:1,historyRevision:2)}
    func backup(room: String) async throws -> Data {Data()}
    func restore(_ bytes: Data,agent: String?,requestId: String) async throws -> Conversation {Conversation(id:"thread:\(requestId)",name:"备份",kind:"direct",agentId:agent,agentIds:[])}
}
func messageFixture(_ id: Int64,client: String? = nil,device: String = "other") -> Message {
    Message(id:id,clientMessageId:client ?? "client-\(id)",deviceId:device,sender:"Alice",platform:"ios",text:"hello",createdAt:1000,conversationId:"home:user-1",role:"user",agentId:nil,replyTo:nil,images:nil,userId:"user-1")
}
func pageFixture(_ messages: [Message],revision: Int64 = 1,jobs: [AgentJob] = []) -> MessagePage {MessagePage(messages:messages,hasMore:false,jobs:jobs,contextOperations:[],historyRevision:revision)}
@MainActor
final class Checks {
    var cases = 0
    func expect(_ condition: Bool,_ message: String) throws {if !condition {throw NativeError(message:message)}}
    func run(_ name: String,_ work: () async throws -> Void) async throws {try await work();cases += 1;print("PASS \(name)")}
    func store(_ disk: MemoryDisk = MemoryDisk(),api: FakeAPI = FakeAPI(),credentials: MemoryCredentials = MemoryCredentials()) async -> ChatStore {
        let result = ChatStore(disk:disk,credentials:credentials,factory:{_,_ in api});await result.initialize();return result
    }
    func settle(_ store: ChatStore) async {
        for _ in 0..<100 {await Task.yield();if !store.sending.isEmpty {break}}
        for _ in 0..<100 {if store.sending.isEmpty {return};try? await Task.sleep(nanoseconds:1_000_000)}
    }
    func runAll(fixtures: URL) async throws {
        try await run("HTTPS endpoint validation") {
            try expect(try Endpoint.normalize("https://example.test/").absoluteString == "https://example.test","endpoint normalization")
            for value in ["http://example.test","https://user:pass@example.test","https://example.test/api","https://example.test?token=x","https://example.test:0"] {
                do {_ = try Endpoint.normalize(value);throw NativeError(message:"accepted unsafe URL \(value)")} catch let error as NativeError {if error.message.hasPrefix("accepted") {throw error}}
            }
        }
        try await run("Chinese mentions and cursor suffix preservation") {
            let text = "你好＠写作 后文",token = MentionCompletion.token(in:text,selection:NSRange(location:4,length:0))!
            let result = MentionCompletion.replacing(token,in:text,with:"writer")
            try expect(result.text == "你好 @writer 后文","mention changed trailing text")
            try expect(MentionCompletion.token(in:"a@example.com",selection:NSRange(location:5,length:0)) == nil,"email matched mention")
        }
        try await run("isolated atomic file persistence") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let disk = FilePersistence(root:root),scope = accountScope(server:"https://example.test",userID:"a")
            let id = try await disk.deviceID();try expect(id == diskID(try await disk.deviceID()),"device identity changed")
            try await disk.save(scope:scope,snapshot:OutboxSnapshot(dismissed:["x"],revisions:["room":2]))
            let read = try await FilePersistence(root:root).load(scope:scope)
            try expect(read.dismissed == ["x"] && read.revisions["room"] == 2,"state did not persist")
            let other = try await disk.load(scope:accountScope(server:"https://example.test",userID:"b"));try expect(other.dismissed.isEmpty,"cross-account leak")
            let file = root.appendingPathComponent("accounts/\(scope)/outbox.json");try Data("invalid".utf8).write(to:file)
            do {_ = try await disk.load(scope:scope);throw NativeError(message:"corrupt queue swallowed")} catch is DecodingError {}
        }
        try await run("ZIP stored and deflated previews / bounded failures") {
            for file in ["stored.zip","deflated.zip"] {let info = try BackupPreview(data:Data(contentsOf:fixtures.appendingPathComponent(file)));try expect(info.name == "测试备份" && info.messageCount == 2,"ZIP preview mismatch")}
            for file in ["invalid.zip","oversize.zip","corrupt.zip"] {
                var rejected = false;do {_ = try BackupPreview(data:Data(contentsOf:fixtures.appendingPathComponent(file)))} catch {rejected = true};try expect(rejected,"invalid ZIP accepted: \(file)")
            }
        }
        try await run("session login saves scoped token only") {
            let credentials = MemoryCredentials(nil),api = FakeAPI();let value = await store(api:api,credentials:credentials)
            let ok = await value.login(address:"https://example.test",serviceToken:"service_secret",username:"Alice")
            let saved = await credentials.read();try expect(ok && saved?.token == "chat_new","login did not save session")
            try expect(value.roomID == "home:user-1","wrong account home");await value.logout();try expect(await credentials.read() == nil,"logout did not remove credential")
        }
        try await run("write before send and POST acknowledgement preserves receive cursor") {
            let disk = MemoryDisk(),api = FakeAPI(),value = await store(disk,api:api)
            try await value.apply(pageFixture([messageFixture(1)]),room:value.roomID,older:false)
            api.sendHook = {outgoing in
                let snapshot = await disk.load(scope:accountScope(server:value.server,userID:value.user!.id))
                guard snapshot.pending.contains(outgoing) else {throw NativeError(message:"sent before persistence")}
                return messageFixture(3,client:outgoing.id,device:outgoing.deviceId)
            }
            value.draft = "发送";await value.sendDraft();await settle(value)
            try expect(api.sends.count == 1 && api.sends[0].platform == "ios","wrong platform or send count")
            try expect(value.pending.isEmpty && value.room.messages.map(\.id) == [1],"POST skipped receive cursor")
            try await value.apply(pageFixture([messageFixture(2),messageFixture(3)]),room:value.roomID,older:false)
            try expect(value.room.messages.map(\.id) == [1,2,3],"missing concurrent message")
        }
        try await run("disk failure retains draft and makes no HTTP send") {
            let disk = MemoryDisk(),api = FakeAPI(),value = await store(disk,api:api);await disk.setFail(true)
            value.draft = "keep me";await value.sendDraft();await settle(value)
            try expect(value.draft == "keep me" && value.pending.isEmpty && api.sends.isEmpty,"lost draft or sent without disk")
        }
        try await run("lost image acknowledgement retries same IDs after restart") {
            let disk = MemoryDisk(),api = FakeAPI(),credentials = MemoryCredentials(),value = await store(disk,api:api,credentials:credentials)
            api.sendHook = {_ in throw NativeError(message:"lost response")}
            let image = DraftImage(id:UUID().uuidString.lowercased(),data:Data([1,2,3]))
            value.draft = "picture";value.draftImages = [image];await value.sendDraft();await settle(value)
            let queued = try value.pending.first.unwrap("pending message lost")
            let restarted = await store(disk,api:api,credentials:credentials);api.sendHook = nil
            await restarted.retry(queued)
            try expect(api.sends.count == 2 && api.sends[0] == api.sends[1],"retry changed message id or body")
            try expect(api.uploads == [image.id,image.id],"retry changed image id");try expect(await disk.imageCount() == 0,"ack did not remove attachment")
        }
        try await run("clearing an LRU-evicted room discards old pending messages") {
            let value = await store(),original = value.roomID
            try await value.apply(pageFixture([],revision:1),room:original,older:false)
            value.pending = [Outgoing(clientMessageId:UUID().uuidString,deviceId:value.deviceID,sender:"Alice",platform:"ios",text:"old",conversationId:original)]
            for index in 0..<10 {value.select("room-\(index)")};value.select(original)
            try await value.apply(pageFixture([],revision:2),room:original,older:false)
            try expect(value.pending.isEmpty,"old messages survived remote clear after eviction")
        }
        try await run("clear removes local pending attachments and persists revision") {
            let disk = MemoryDisk(),value = await store(disk),scope = accountScope(server:value.server,userID:value.user!.id)
            let image = DraftImage(id:UUID().uuidString.lowercased(),data:Data([1,2,3]));await disk.saveImage(image,scope:scope)
            value.pending = [Outgoing(clientMessageId:UUID().uuidString,deviceId:value.deviceID,sender:"Alice",platform:"ios",text:"old",conversationId:value.roomID,imageIds:[image.id])]
            try await value.clearLocal(value.roomID,revision:2)
            try expect(await disk.imageCount() == 0 && value.pending.isEmpty,"clear leaked private image")
            try expect(await disk.load(scope:scope).revisions[value.roomID] == 2,"clear revision not persisted")
        }
        try await run("multi-image batches stay in origin conversation") {
            let value = await store();value.select("a");let origin = value.imageOrigin
            let first = value.beginImage(origin:origin)!,second = value.beginImage(origin:origin)!
            value.select("b")
            value.finishImage(first,image:DraftImage(id:UUID().uuidString,data:Data([1])))
            value.finishImage(second,image:DraftImage(id:UUID().uuidString,data:Data([2])))
            try expect(value.draftImages.isEmpty,"image leaked into B draft")
            value.select("a");try expect(value.draftImages.count == 2,"origin batch lost")
        }
        try await run("clearing cancels unfinished image imports") {
            let value = await store(),work = value.beginImage(origin:value.imageOrigin)!
            try await value.clearLocal(value.roomID,revision:2);value.finishImage(work,image:DraftImage(id:UUID().uuidString,data:Data([1])))
            try expect(value.draftImages.isEmpty,"late image reappeared after clear")
        }
        try await run("draft text survives navigation") {
            let value = await store();value.select("a");value.draft = "A";value.select("b");value.draft = "B";value.select("a");try expect(value.draft == "A","draft lost");value.select("b");try expect(value.draft == "B","draft crossed rooms")
        }
        try await run("queued private chat creation never steals a later navigation") {
            let api = FakeAPI(),value = await store(api:api)
            let agent = AgentInfo(id:UUID().uuidString.lowercased(),name:"A",handle:"a",provider:"openai",model:nil,enabled:true,avatarId:nil,description:nil)
            api.directHook = {id in
                try await Task.sleep(nanoseconds:10_000_000)
                return Conversation(id:"dm:user-1:\(id)",name:"A",kind:"direct",agentId:id,agentIds:[id])
            }
            value.navigate(to:agent);value.select("group:chosen-later");value.draft = "stay here"
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds:1_000_000)
                try expect(value.roomID == "group:chosen-later" && value.draft == "stay here","queued creation stole navigation or draft")
            }
            try expect(value.opening.isEmpty,"background creation did not finish")
        }
        try await run("dismissed failures persist and reset after running state") {
            let disk = MemoryDisk(),value = await store(disk),job = AgentJob(messageId:1,agentId:"a",agentName:"A",status:"FAILED",error:"first")
            try await value.apply(pageFixture([],jobs:[job]),room:value.roomID,older:false);await value.dismiss(job);try expect(value.visibleJobs.isEmpty,"dismiss ignored")
            let reopened = await store(disk);try await reopened.apply(pageFixture([],jobs:[job]),room:reopened.roomID,older:false);try expect(reopened.visibleJobs.isEmpty,"dismiss not restored")
            let running = AgentJob(messageId:1,agentId:"a",agentName:"A",status:"RUNNING",error:"")
            try await reopened.apply(pageFixture([],jobs:[running]),room:reopened.roomID,older:false);try expect(reopened.ignored.isEmpty,"running job retained old dismissal")
        }
        try await run("usage failure preserves last successful data") {
            let api = FakeAPI(),value = await store(api:api)
            api.usageHook = {[try JSONDecoder().decode(ModelUsage.self,from:Data(#"{"provider":"openai","model":"gpt-4o","inputTokens":1000000,"outputTokens":1000000,"totalTokens":2000000,"reportedCalls":1,"unreportedCalls":0}"#.utf8))]}
            await value.loadUsage();let date = value.usageLoadedAt
            api.usageHook = {throw NativeError(message:"offline")};await value.loadUsage()
            try expect(value.usage.count == 1 && value.usageLoadedAt == date && value.usageError != nil,"usage failure erased data")
            let cost = UsagePricing.estimate(value.usage[0])!;try expect(cost.low == 11.25 && cost.high == 12.5,"pricing diverged")
        }
        try await run("session expiration clears in-memory account and credentials") {
            let credentials = MemoryCredentials(),value = await store(credentials:credentials)
            value.savingDraft = true;value.clearingHistory = true
            let result: Bool? = await value.tool("test") {_ in throw NativeError(message:"expired",status:401)}
            try expect(result == nil && !value.loggedIn && value.user == nil,"expired account remained active")
            try expect(await credentials.read() == nil,"expired credentials persisted")
            try expect(!value.savingDraft && !value.clearingHistory,"old storage operation blocked the next login")
        }
        try await run("redirect never forwards credentials") {
            let delegate = NoRedirect(),session = URLSession(configuration:.ephemeral),url = URL(string:"https://example.test")!
            defer {session.invalidateAndCancel()};let task = session.dataTask(with:url)
            let response = HTTPURLResponse(url:url,statusCode:302,httpVersion:nil,headerFields:["Location":"https://other.test"])!
            var followed = true
            delegate.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:"https://other.test")!)) {followed = $0 != nil}
            try expect(!followed,"redirect forwarded credential request")
        }
        try await checkHTTPContracts()
        try await checkNotifications()
        try await checkDocuments()
        try await checkCollections()
        try await checkBranches()
        try await checkSearch()
        try await checkTimeline()
        try await checkParity()
        print("Native core: \(cases) scenarios passed")
    }
}
private extension Optional {func unwrap(_ message: String) throws -> Wrapped {guard let self else {throw NativeError(message:message)};return self}}
private func diskID(_ value: String) -> String {value}
@main struct NativeChecks {
    @MainActor static func main() async {
        do {try await Checks().runAll(fixtures:URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true))}
        catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
    }
}

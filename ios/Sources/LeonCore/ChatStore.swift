import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    func openQuotedRoom(_ id:String) {select(id)}
    @Published var branchMessage:Message?
    func beginBranch(_ message:Message) {
        guard message.id>0,message.conversationId == roomID,api != nil else {return}
        branchMessage=message
    }
    func createBranch(_ message:Message,name:String,requestId:String) async throws -> Conversation {
        guard message.id>0,let room=message.conversationId,let api else {throw NativeError(message:"请先登录服务器并选择已发送成功的消息。")}
        let connection=connectionID
        do {
            let result=try await api.branch(room:room,message:message.id,name:name,requestId:requestId)
            guard connection==connectionID,!Task.isCancelled else {throw CancellationError()}
            upsert(result)
            return result
        } catch {
            if connection==connectionID,(error as? NativeError)?.expired == true {await handle(error,connection:connection)}
            throw error
        }
    }
    @Published var quotedMessage: MessageQuote?
    private var quoteDrafts: [String:MessageQuote] = [:]
    @Published var collectionNotice = ""
    private var favoriteRequests = Set<Int64>()
    func quoteMessage(_ message:Message) {
        guard message.id>0, message.conversationId == roomID else {return}
        quotedMessage=MessageQuote(message:message)
    }
    func cancelQuote(){quotedMessage=nil}
    func favoriteMessage(_ message:Message) async {
        guard message.id>0,let api,!favoriteRequests.contains(message.id) else {return}
        let connection=connectionID;favoriteRequests.insert(message.id)
        defer {if connection==connectionID {favoriteRequests.remove(message.id)}}
        do {_ = try await api.addFavorite(message.id);guard connection==connectionID else {return};showNotice("已收藏")}
        catch {if connection==connectionID {await handle(error,connection:connection)}}
    }
    func favoritePage(query:String,before:Int64?) async throws -> FavoritePage {
        guard let api else {throw NativeError(message:"请先登录服务器。")}
        let connection=connectionID
        do {
            let result=try await api.favorites(query:query,before:before)
            guard self.api === api else {throw CancellationError()};return result
        } catch {if let failure=error as? NativeError,failure.expired {await handle(failure,connection:connection)};throw error}
    }
    func deleteFavorite(_ id:Int64) async throws {
        guard let api else {throw NativeError(message:"请先登录服务器。")};let connection=connectionID
        do {
            try await api.removeFavorite(id);guard self.api === api else {throw CancellationError()}
            favoritePictures = favoritePictures.filter {!$0.key.hasPrefix("\(id):")}
        }
        catch {if let failure=error as? NativeError,failure.expired {await handle(failure,connection:connection)};throw error}
    }
    func favoriteImage(_ favorite:Int64,image:String,retry:Bool=false) async throws -> Data {
        try Task.checkCancellation()
        let key = "\(favorite):\(image)"
        if retry {favoritePictures.removeValue(forKey:key)}
        if let data = favoritePictures[key] {return data}
        guard let api else {throw NativeError(message:"请先登录服务器。")};let connection=connectionID
        do {
            let data=try await api.favoriteImage(favorite,image:image)
            guard self.api === api,!Task.isCancelled else {throw CancellationError()}
            if favoritePictures.count >= 16 {favoritePictures.removeAll()}
            favoritePictures[key] = data
            return data
        }
        catch {if let failure=error as? NativeError,failure.expired {await handle(failure,connection:connection)};throw error}
    }
    func conversationForOpening(_ id:String) async throws -> Conversation {
        try Task.checkCancellation()
        if let room = conversations.first(where:{$0.id == id}) {return room}
        guard let api else {throw NativeError(message:"请先登录服务器。")}
        let connection = connectionID
        do {
            let rooms = try await api.conversations()
            guard self.api === api,!Task.isCancelled else {throw CancellationError()}
            guard let room = rooms.first(where:{$0.id == id}) else {
                throw NativeError(message:"该会话暂不可用，可能已删除或你已不在会话中。请刷新后重试。")
            }
            upsert(room)
            return room
        } catch {
            if let failure=error as? NativeError,failure.expired {await handle(failure,connection:connection)}
            throw error
        }
    }
    var searchConnectionID: ObjectIdentifier? { api.map { ObjectIdentifier($0) } }
    func searchMessages(query: String, room: String?, before: Int64?) async throws -> ChatSearchPage {
        guard let api else { throw NativeError(message:"请先登录服务器。") }
        let connection = connectionID
        do {
            let result = try await api.search(query:query,room:room,before:before)
            guard self.api === api else { throw CancellationError() }
            return result
        } catch {
            if let failure = error as? NativeError, failure.expired { await handle(failure,connection:connection) }
            throw error
        }
    }
    func searchHistory(room: String, message: Int64, direction: String) async throws -> ChatSearchContext {
        guard let api else { throw NativeError(message:"请先登录服务器。") }
        let connection = connectionID
        do {
            let result = try await api.searchContext(room:room,message:message,direction:direction)
            guard self.api === api else { throw CancellationError() }
            return result
        } catch {
            if let failure = error as? NativeError, failure.expired { await handle(failure,connection:connection) }
            throw error
        }
    }
    struct RoomState {
        var messages: [Message] = []; var jobs: [AgentJob] = []; var operations: [ContextOperation] = []
        var loaded = false; var hasOlder = false
    }
    typealias APIFactory = (URL, String) -> any ChatAPI
    let disk: any Persistence
    let credentials: any CredentialStorage
    let factory: APIFactory
    @Published var user: ChatUser?
    @Published var server = "https://121.40.254.112"
    @Published var status = "尚未登录"
    @Published var error: String?
    @Published private(set) var notice: UserNotice?
    @Published var agents: [AgentInfo] = []
    @Published var conversations: [Conversation] = []
    @Published var roomID = "shared"
    @Published var room = RoomState()
    @Published var draft = ""
    @Published var draftDocuments:[DraftDocument]=[]
    @Published var importingDocuments=false
    private var documentDrafts:[String:[DraftDocument]]=[:]
    private var documentGeneration=UUID()
    func addDocuments(_ urls:[URL],origin:ImageOrigin){
        guard loggedIn,!importingDocuments,!clearingHistory,origin.connection==connectionID else {return}
        let count=origin.room==roomID ? draftDocuments.count : documentDrafts[origin.room]?.count ?? 0
        guard count+urls.count<=4 else {error="每条消息最多发送 4 个文档。";return}
        importingDocuments=true;let stamp=documentGeneration
        Task {
            do {
                let files=try await Task.detached(priority:.userInitiated){try urls.map {try DraftDocument.read($0)}}.value
                guard stamp==documentGeneration,origin.connection==connectionID else {return}
                if origin.room==roomID {draftDocuments+=files}else{documentDrafts[origin.room,default:[]]+=files}
            }catch {if stamp==documentGeneration {self.error=error.localizedDescription}}
            if stamp==documentGeneration {importingDocuments=false}
        }
    }
    var notificationAPI:(any NotificationAPI)? {api as? any NotificationAPI}
    var notificationDevice:String {deviceID}
    var documentRoom:String {roomID}
    func addDocuments(_ urls:[URL],room:String,connection:ObjectIdentifier?){guard searchConnectionID==connection else {return};addDocuments(urls,origin:ImageOrigin(connection:connectionID,room:room))}
    func removeDocument(_ id:String){draftDocuments.removeAll {$0.id==id}}
    func documentData(_ id:String,favorite:Int64?=nil) async throws -> Data {
        guard let api else {throw NativeError(message:"请先登录。")};let connection=connectionID
        do {let data=try await api.document(id,favorite:favorite);guard connection==connectionID else {throw CancellationError()};return data}
        catch {await handle(error,connection:connection);throw error}
    }
    @Published var draftImages: [DraftImage] = []
    @Published var preparingImages = 0
    @Published var pending: [Outgoing] = []
    @Published var sending = Set<String>()
    @Published var ignored = Set<String>()
    @Published var busy: String?
    @Published var configuring = false
    @Published var connected = false
    @Published var loadingOlder = false
    @Published var savingDraft = false
    @Published var clearingHistory = false
    @Published var opening = Set<String>()
    @Published var usage: [ModelUsage] = []
    @Published var usageLoadedAt: Date?
    @Published var usageError: String?
    @Published var loadingUsage = false
    private(set) var connectionID = UUID()
    private(set) var deviceID = ""
    private(set) var api: (any ChatAPI)?
    private(set) var storageHealthy = true
    private var scope: String?
    private var active = false
    private var generation = UUID()
    private var poller: Task<Void,Never>?
    private var directoryTask: Task<Void,Never>?
    private var creationTasks: [String:Task<Conversation,Error>] = [:]
    private var drafts: [String:String] = [:]
    private var imageDrafts: [String:[DraftImage]] = [:]
    private var cache: [String:RoomState] = [:]
    private var cacheOrder: [String] = []
    // Revisions outlive the LRU cache so remote clearing cannot revive old outbox entries.
    private var revisions: [String:Int64] = [:]
    private var imageWork: [UUID:ImageOrigin] = [:]
    private var avatars: [String:Data] = [:]
    private var pictures: [String:Data] = [:]
    private var favoritePictures: [String:Data] = [:]
    private var noticeTask: Task<Void,Never>?
    var loggedIn: Bool { api != nil }
    var selected: Conversation? { conversations.first { $0.id == roomID } }
    var canSend: Bool { loggedIn && storageHealthy && !configuring && busy == nil && !savingDraft && !clearingHistory && !opening.contains(roomID) && preparingImages == 0 && !importingDocuments && draft.utf16.count <= 8000 && (!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !draftImages.isEmpty || !draftDocuments.isEmpty) }
    var visibleJobs: [AgentJob] { room.jobs.filter { !$0.failed || !ignored.contains($0.dismissal) } }
    var dismissedCount: Int { room.jobs.count-visibleJobs.count }
    var currentPending: [Outgoing] { pending.filter { $0.conversationId == roomID } }
    var availableAgents: [AgentInfo] { agents.filter { $0.enabled && (roomID == "shared" || roomID.hasPrefix("home:") || selected?.agentIds.contains($0.id) == true) } }
    var imageOrigin: ImageOrigin { ImageOrigin(connection:connectionID,room:roomID) }
    func agent(_ id: String?) -> AgentInfo? { agents.first { $0.id == id } }
    func mine(_ m: Message) -> Bool { (m.role ?? "user") == "user" && (user.map { m.userId == $0.id } ?? (m.deviceId == deviceID)) }
    func owns(_ c: Conversation) -> Bool { user != nil && (c.ownerId == user!.id || (c.ownerId?.isEmpty ?? true) && user!.home == "shared") }
    func managesGroup(_ c:Conversation) -> Bool {c.kind == "group" && c.id != "shared" && !c.id.hasPrefix("home:") && owns(c)}
    func showNotice(_ text:String) {
        noticeTask?.cancel();let value = UserNotice(text:text),connection = connectionID;notice = value
        noticeTask = Task { [weak self] in
            do {try await Task.sleep(nanoseconds:3_000_000_000)} catch {return}
            guard let self,self.connectionID == connection,self.notice?.id == value.id else {return};self.notice = nil
        }
    }
    init(disk: any Persistence, credentials: any CredentialStorage, factory: @escaping APIFactory = { MessageAPI(base:$0,token:$1) }) {
        self.disk = disk; self.credentials = credentials; self.factory = factory
    }
    func initialize() async {
        do {
            deviceID = try await disk.deviceID()
            if let saved = try await credentials.read() {
                server = saved.server; user = saved.user
                api = factory(try Endpoint.normalize(server),saved.token); roomID = saved.user.home
                try await restoreOutbox()
            }
        } catch { storageHealthy = false; self.error = "无法读取本地登录或待发记录：\(error.localizedDescription)" }
    }
    private func restoreOutbox() async throws {
        guard let user else { return }
        scope = accountScope(server:server,userID:user.id)
        let snapshot = try await disk.load(scope:scope!)
        pending = snapshot.pending; ignored = snapshot.dismissed; revisions = snapshot.revisions; storageHealthy = true
    }
    private func persist() async throws {
        guard let scope, storageHealthy else { throw NativeError(message:"本地待发记录不可用，未发送新消息。") }
        try await disk.save(scope:scope,snapshot:OutboxSnapshot(pending:pending,dismissed:ignored,revisions:revisions))
    }
    func login(address: String, serviceToken: String, username: String) async -> Bool {
        guard !loggedIn, !configuring else { return false }
        configuring = true; defer { configuring = false; restart() }
        do {
            let base = try Endpoint.normalize(address), name = username.trimmingCharacters(in:.whitespacesAndNewlines), token = serviceToken.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !name.isEmpty, name.utf16.count <= 60, !name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),
                  !token.isEmpty, token.count <= 900, !token.contains(where:{$0.isWhitespace}), !token.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains)
            else { throw NativeError(message:"请填写服务访问令牌和 1–60 字的 UserName。") }
            let result = try await factory(base,token).login(name)
            guard result.sessionToken.hasPrefix("chat_"), !result.user.id.isEmpty else { throw NativeError(message:"登录响应无效。") }
            let candidate = factory(base,result.sessionToken)
            // Load local data before committing credentials or replacing account state.
            let newScope = accountScope(server:base.absoluteString,userID:result.user.id)
            do {
                let snapshot = try await disk.load(scope:newScope)
                try await credentials.save(Credentials(server:base.absoluteString,user:result.user,token:result.sessionToken))
                reset(); server = base.absoluteString; user = result.user; api = candidate; roomID = result.user.home
                scope = newScope; pending = snapshot.pending; ignored = snapshot.dismissed; revisions = snapshot.revisions; storageHealthy = true; status = "正在同步…"
            } catch { try? await candidate.logout(); throw error }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func logout() async {
        guard let api, !configuring else { return }
        guard busy == nil, sending.isEmpty, !savingDraft else { error = "请等待当前聊天操作完成。"; return }
        configuring = true; defer { configuring = false }
        do {
            do { try await api.logout() } catch let failure as NativeError where failure.expired { }
            try await credentials.save(nil); reset(); status = "已退出登录"
        } catch { await handle(error,connection:connectionID) }
    }
    private func reset() {
        noticeTask?.cancel();noticeTask = nil;notice = nil
        poller?.cancel(); directoryTask?.cancel(); creationTasks.values.forEach { $0.cancel() }; creationTasks = [:]
        connectionID = UUID(); generation = UUID(); api = nil; user = nil; scope = nil
        connected = false; roomID = "shared"; room = RoomState(); agents = []; conversations = []; pending = []; sending = []; ignored = []
        quotedMessage=nil;quoteDrafts=[:];favoriteRequests=[];favoritePictures=[:];collectionNotice=""
        documentGeneration=UUID();draftDocuments=[];documentDrafts=[:];importingDocuments=false
        draft = ""; draftImages = []; drafts = [:]; imageDrafts = [:]; cache = [:]; cacheOrder = []; revisions = [:]; avatars = [:]; pictures = [:]
        imageWork = [:]; preparingImages = 0; busy = nil; opening = []; loadingOlder = false; usage = []; usageLoadedAt = nil; usageError = nil; loadingUsage = false
        savingDraft = false; clearingHistory = false
    }
    private func handle(_ failure: Error, connection: UUID) async {
        guard connection == connectionID else { return }
        if let failure = failure as? NativeError, failure.expired {
            configuring = true; reset(); try? await credentials.save(nil); configuring = false; status = "登录已失效，请重新登录。"
        } else if !(failure is CancellationError) { error = failure.localizedDescription }
    }
    func setActive(_ value: Bool) {
        active = value
        if value { restart() } else { poller?.cancel(); directoryTask?.cancel(); connected = false; status = "已暂停 · 返回后自动同步" }
    }
    private func restart() {
        guard active, loggedIn, !configuring else { return }
        directoryTask?.cancel(); let connection = connectionID
        directoryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.connectionID == connection else { return }
                await self.refreshDirectory()
                do { try await Task.sleep(nanoseconds:10_000_000_000) } catch { return }
            }
        }
        refresh()
    }
    func refreshDirectory() async {
        guard let api else { return }; let connection = connectionID
        async let directory = api.agents(); async let rooms = api.conversations()
        async let presence: Void? = try? api.heartbeat(deviceId:deviceID,name:user?.username ?? "iPhone")
        do {
            let (newAgents,newRooms) = try await (directory,rooms)
            guard connection == connectionID, !Task.isCancelled else { return }
            agents = newAgents
            conversations = newRooms + conversations.filter { old in (opening.contains(old.id) || old.id == roomID) && !newRooms.contains(where:{$0.id == old.id}) }
        } catch { if !Task.isCancelled { await handle(error,connection:connection) } }
        _ = await presence
    }
    func select(_ id: String) {
        guard id != roomID else { return }
        quoteDrafts[roomID]=quotedMessage
        drafts[roomID] = draft; imageDrafts[roomID] = draftImages;documentDrafts[roomID]=draftDocuments
        var kept = room; kept.hasOlder = kept.hasOlder || kept.messages.count > 300; kept.messages = Array(kept.messages.suffix(300))
        cache[roomID] = kept; cacheOrder.removeAll {$0 == roomID}; cacheOrder.append(roomID)
        while cacheOrder.count > 8 { cache.removeValue(forKey:cacheOrder.removeFirst()) }
        roomID = id; room = cache.removeValue(forKey:id) ?? RoomState(); cacheOrder.removeAll {$0 == id}
        quotedMessage=quoteDrafts[id]
        draft = drafts[id] ?? ""; draftImages = imageDrafts[id] ?? [];draftDocuments=documentDrafts[id] ?? []; generation = UUID(); loadingOlder = false; updateImageCount(); refresh()
    }
    func upsert(_ conversation: Conversation) { conversations.removeAll {$0.id == conversation.id}; conversations.append(conversation) }
    func navigate(to agent: AgentInfo) {
        let primary = user?.home == "shared" ? "direct:\(agent.id)" : "dm:\(user?.id ?? ""):\(agent.id)"
        if let known = conversations.first(where:{$0.id == primary}) ?? conversations.first(where:{$0.direct && $0.agentId == agent.id}), !opening.contains(known.id) { select(known.id); return }
        let provisional = Conversation(id:primary,name:agent.name,kind:"direct",agentId:agent.id,agentIds:[agent.id])
        upsert(provisional); opening.insert(primary); select(primary)
        let connection = connectionID
        Task { if connection == connectionID { await open(agent) } }
    }
    func open(_ agent: AgentInfo) async {
        let primary = user?.home == "shared" ? "direct:\(agent.id)" : "dm:\(user?.id ?? ""):\(agent.id)"
        let existing = conversations.first {$0.id == primary} ?? conversations.first {$0.direct && $0.agentId == agent.id}
        if let existing, !opening.contains(existing.id) { return }
        guard let api else { return }; let connection = connectionID
        let provisional = existing ?? Conversation(id:primary,name:agent.name,kind:"direct",agentId:agent.id,agentIds:[agent.id])
        // Navigation happens synchronously in navigate(to:). A queued network
        // task must not select its room after the user has already moved on.
        upsert(provisional); opening.insert(provisional.id)
        let task: Task<Conversation,Error>
        if let pending = creationTasks[agent.id] { task = pending }
        else { task = Task { try await api.direct(agent.id) }; creationTasks[agent.id] = task }
        defer { if connection == connectionID { creationTasks.removeValue(forKey:agent.id) } }
        do {
            let conversation = try await task.value
            guard connection == connectionID else { return }
            opening.remove(provisional.id); upsert(conversation)
            if provisional.id != conversation.id { conversations.removeAll {$0.id == provisional.id} }
            if roomID == provisional.id { select(conversation.id); refresh() }
        } catch { await handle(error,connection:connection) }
    }
    func refresh() {
        poller?.cancel()
        guard active, let api, !opening.contains(roomID) else { return }
        let current = generation, connection = connectionID, selected = roomID
        poller = Task { [weak self] in
            var delay: UInt64 = 2
            while !Task.isCancelled {
                guard let self, current == self.generation else { return }
                do {
                    let after = self.room.loaded ? self.room.messages.last?.id ?? 0 : nil
                    let page = try await api.page(room:selected,after:after,before:nil)
                    guard current == self.generation, !Task.isCancelled else { return }
                    if try await self.apply(page,room:selected,older:false) { continue }
                    self.connected = true; self.status = "已连接 · 自动同步"; delay = 2
                    if after != nil && page.hasMore { continue }
                } catch {
                    guard current == self.generation, !Task.isCancelled else { return }
                    self.connected = false; self.status = error.localizedDescription; delay = min(delay*2,30)
                    if (error as? NativeError)?.expired == true { await self.handle(error,connection:connection); return }
                }
                do { try await Task.sleep(nanoseconds:delay*1_000_000_000) } catch { return }
            }
        }
    }
    @discardableResult
    func apply(_ page: MessagePage, room id: String, older: Bool) async throws -> Bool {
        guard id == roomID else { return false }
        if let revision = page.historyRevision {
            let previous = revisions.updateValue(revision,forKey:id)
            if let previous, previous != revision { try await clearLocal(id,revision:revision); return true }
        }
        if !room.loaded || older { room.hasOlder = page.hasMore }
        room.loaded = true
        var merged = Dictionary(uniqueKeysWithValues:room.messages.map {($0.id,$0)})
        for message in page.messages { merged[message.id] = message }
        room.messages = merged.values.sorted {$0.id < $1.id}
        room.jobs = page.jobs ?? []; room.operations = page.contextOperations ?? []
        let activeJobs = Set(room.jobs.filter {!$0.failed}.map(\.id))
        let oldIgnored = ignored; ignored = ignored.filter {!activeJobs.contains(String($0.split(separator:"#",maxSplits:1).first ?? ""))}
        let confirmed = Set(page.messages.filter {$0.deviceId == deviceID}.map(\.clientMessageId))
        let acknowledgements = pending.filter {confirmed.contains($0.clientMessageId)}
        if !acknowledgements.isEmpty { try await acknowledge(acknowledgements) }
        else if oldIgnored != ignored { try await persist() }
        return false
    }
    func older() async {
        guard let api, room.hasOlder, let first = room.messages.first, !loadingOlder else { return }
        let current = generation, connection = connectionID, selected = roomID
        loadingOlder = true; defer { if current == generation { loadingOlder = false } }
        do { let page = try await api.page(room:selected,after:nil,before:first.id); guard current == generation else { return }; if try await apply(page,room:selected,older:true) { refresh() } }
        catch { await handle(error,connection:connection) }
    }
    func beginImage(origin: ImageOrigin) -> UUID? {
        guard loggedIn, !configuring, !clearingHistory, origin.connection == connectionID, (origin.room == roomID ? draftImages.count : imageDrafts[origin.room]?.count ?? 0) + imageWork.values.filter({$0 == origin}).count < 4 else { return nil }
        let id = UUID(); imageWork[id] = origin; updateImageCount(); return id
    }
    func finishImage(_ id: UUID, image: DraftImage?, failure: Error? = nil) {
        guard let origin = imageWork.removeValue(forKey:id), origin.connection == connectionID else { return }
        if let image {
            if origin.room == roomID { draftImages.append(image) }
            else { imageDrafts[origin.room,default:[]].append(image) }
        }
        if let failure { error = failure.localizedDescription }; updateImageCount()
    }
    private func updateImageCount() { preparingImages = imageWork.values.filter {$0.connection == connectionID && $0.room == roomID}.count }
    func removeImage(_ id: String) { draftImages.removeAll {$0.id == id} }
    func sendDraft() async {
        guard canSend, let scope, let user else { return }
        let original = draft, selected = roomID, connection = connectionID, images = draftImages, quote = quotedMessage, documents=draftDocuments
        let outgoing = Outgoing(clientMessageId:UUID().uuidString.lowercased(),deviceId:deviceID,sender:user.username,platform:"ios",text:original.trimmingCharacters(in:.whitespacesAndNewlines),conversationId:selected,imageIds:images.map(\.id),quoteMessageId:quote?.id,documentIds:documents.map(\.id),quote:quote,documents:documents.map(\.attachment))
        savingDraft = true; defer { if connection == connectionID { savingDraft = false } }
        do {
            for document in documents {try await disk.saveDocument(document,scope:scope)}
            for image in images { try await disk.saveImage(image,scope:scope) }
            guard connection == connectionID else { return }
            pending.append(outgoing)
            do { try await persist() } catch { pending.removeAll {$0.id == outgoing.id}; throw error }
            guard connection == connectionID else { return }
            if roomID == selected {
                if quotedMessage == quote {quotedMessage=nil}
                if draft == original { draft = "" }
                draftDocuments.removeAll {old in documents.contains {$0.id==old.id}}
                draftImages.removeAll { old in images.contains(where:{$0.id == old.id}) }
            } else {
                if quoteDrafts[selected] == quote {quoteDrafts.removeValue(forKey:selected)}
                if drafts[selected] == original { drafts[selected] = "" }
                documentDrafts[selected]?.removeAll {old in documents.contains {$0.id==old.id}}
                imageDrafts[selected]?.removeAll { old in images.contains(where:{$0.id == old.id}) }
            }
            Task { await retry(outgoing) }
        } catch { await handle(error,connection:connection) }
    }
    private func acknowledge(_ items: [Outgoing]) async throws {
        guard let scope else { return }; let connection = connectionID, ids = Set(items.map(\.id))
        pending.removeAll {ids.contains($0.id)}
        do { try await persist() } catch { if connection == connectionID { for item in items where !pending.contains(where:{$0.id == item.id}) { pending.append(item) } }; throw error }
        if connection == connectionID { try await disk.removeImages(items.flatMap(\.imageIds),scope:scope);try await disk.removeDocuments(items.flatMap {$0.documentIds ?? []},scope:scope) }
    }
    func retry(_ message: Outgoing) async {
        guard let api, let scope, !sending.contains(message.id), !configuring else { return }
        let connection = connectionID; sending.insert(message.id); defer { if connection == connectionID { sending.remove(message.id) } }
        do {
            for document in message.documents ?? [] {
                guard let bytes=try await disk.document(document.id,scope:scope) else {throw NativeError(message:"待发文档缺失，消息尚未发送。")}
                guard connection==connectionID else {return};try await api.uploadDocument(document,room:message.conversationId,data:bytes)
            }
            for id in message.imageIds {
                guard let bytes = try await disk.image(id,scope:scope) else { throw NativeError(message:"待发图片缺失，消息尚未发送。") }
                try await api.uploadImage(id:id,room:message.conversationId,data:bytes)
            }
            guard connection == connectionID else { return }
            _ = try await api.send(message)
            guard connection == connectionID else { return }
            try await acknowledge([message]); refresh()
        } catch { await handle(error,connection:connection) }
    }
    func dismiss(_ job: AgentJob) async { guard job.failed else { return }; ignored.insert(job.dismissal); do { try await persist() } catch { self.error = error.localizedDescription } }
    func restoreDismissals() async { room.jobs.forEach {ignored.remove($0.dismissal)}; do { try await persist() } catch { self.error = error.localizedDescription } }
    func clearLocal(_ id: String, revision: Int64) async throws {
        let connection = connectionID, oldScope = scope
        clearingHistory = true; defer {if connection == connectionID {clearingHistory = false}}
        revisions[id] = revision; cache.removeValue(forKey:id); cacheOrder.removeAll {$0 == id}; drafts.removeValue(forKey:id); imageDrafts.removeValue(forKey:id)
        imageWork = imageWork.filter {$0.value.room != id}; updateImageCount()
        let removed = pending.filter {$0.conversationId == id}; pending.removeAll {$0.conversationId == id}
        documentGeneration=UUID();importingDocuments=false;documentDrafts.removeValue(forKey:id);if roomID==id {draftDocuments=[]}
        quoteDrafts.removeValue(forKey:id);if roomID == id {quotedMessage=nil}
        if roomID == id {room = RoomState();draft = "";draftImages = [];generation = UUID();loadingOlder = false}
        do {try await persist();if let oldScope {try await disk.removeImages(removed.flatMap(\.imageIds),scope:oldScope);try await disk.removeDocuments(removed.flatMap {$0.documentIds ?? []},scope:oldScope)}}
        catch {if connection == connectionID {storageHealthy = false};throw error}
        if connection == connectionID && roomID == id {refresh()}
    }
    func tool<T>(_ label: String, work: (any ChatAPI) async throws -> T) async -> T? {
        guard let api, busy == nil, !configuring, !opening.contains(roomID) else { return nil }
        let connection = connectionID, selected = roomID; busy = label
        defer { if connection == connectionID { busy = nil } }
        do { let value = try await work(api); return connection == connectionID && selected == roomID ? value : nil }
        catch { await handle(error,connection:connection); return nil }
    }
    func loadUsage() async {
        guard let api, !loadingUsage else { return }; let connection = connectionID
        loadingUsage = true; usageError = nil; defer { if connection == connectionID { loadingUsage = false } }
        do { let rows = try await api.usage(); guard connection == connectionID else { return }; usage = rows; usageLoadedAt = Date() }
        catch { if connection == connectionID { usageError = error.localizedDescription; if (error as? NativeError)?.expired == true { await handle(error,connection:connection) } } }
    }
    func imageData(_ id: String, retry: Bool = false) async throws -> Data {
        if retry { pictures.removeValue(forKey:id) }
        if let data = pictures[id] { return data }
        guard let api, let scope else { throw NativeError(message:"请先登录。") }; let connection = connectionID
        let data: Data
        let local = try await disk.image(id,scope:scope)
        guard connection == connectionID,!Task.isCancelled else {throw CancellationError()}
        if let local { data = local } else { data = try await api.image(id) }
        guard connection == connectionID,!Task.isCancelled else {throw CancellationError()}
        if pictures.count >= 48 { pictures.removeAll() };pictures[id] = data;return data
    }
    func avatarData(_ id: String) async throws -> Data {
        if let data = avatars[id] { return data }; guard let api else { throw NativeError(message:"请先登录。") }
        let connection = connectionID, data = try await api.avatar(id)
        guard connection == connectionID,!Task.isCancelled else {throw CancellationError()}
        if avatars.count >= 64 { avatars.removeAll() };avatars[id] = data;return data
    }
}

import Foundation

@MainActor
extension Checks {
    func checkCollections() async throws {
        try await run("favorite navigation resolves an uncached room and preserves the current draft") {
            let api=FakeAPI(),value=await store(api:api)
            let room=Conversation(id:"group:remote",name:"另一设备新建",kind:"group",agentId:nil,agentIds:[])
            var requests=0
            api.conversationsHook={requests+=1;return [room]}
            value.draft="保留草稿"
            try expect(value.conversations.isEmpty,"fixture unexpectedly has a cached directory")
            let resolved=try await value.conversationForOpening(room.id)
            try expect(resolved.id==room.id && value.conversations.contains(where:{$0.id==room.id}),"remote room was not resolved or cached")
            try expect(value.roomID=="home:user-1" && value.draft=="保留草稿","resolving navigated or discarded the draft")
            _ = try await value.conversationForOpening(room.id)
            try expect(requests==1,"cached room repeated directory fetch")
        }
        try await run("favorite navigation reports missing rooms and network failures without changing chats") {
            let api=FakeAPI(),value=await store(api:api)
            for offline in [false,true] {
                api.conversationsHook={if offline {throw NativeError(message:"offline")};return []}
                var failure:String?
                do {_ = try await value.conversationForOpening("group:missing")}
                catch {failure=error.localizedDescription}
                try expect(failure?.contains(offline ? "offline" : "暂不可用")==true,"navigation failed without actionable feedback")
                try expect(value.roomID=="home:user-1","failed navigation changed the current room")
            }
        }
        try await run("favorite navigation rejects cancelled and previous-account directory responses") {
            for logout in [false,true] {
                let api=FakeAPI(),value=await store(api:api)
                var release:CheckedContinuation<[Conversation],Never>?
                api.conversationsHook={await withCheckedContinuation {release=$0}}
                let task=Task {try await value.conversationForOpening("group:old")}
                while release==nil {await Task.yield()}
                if logout {await value.logout()} else {task.cancel()}
                release!.resume(returning:[Conversation(id:"group:old",name:"旧账号",kind:"group",agentId:nil,agentIds:[])])
                do {_ = try await task.value;throw NativeError(message:"late directory was accepted")}
                catch is CancellationError {}
                try expect(value.conversations.isEmpty,"cancelled directory response changed the room cache")
            }
        }
        try await run("favorite image cache isolates favorite IDs and evicts removed favorites") {
            let api=FakeAPI(),value=await store(api:api)
            var requests=0
            api.favoriteImageHook={favorite,_ in requests+=1;return Data([UInt8(favorite)])}
            let first=try await value.favoriteImage(1,image:"image")
            let cached=try await value.favoriteImage(1,image:"image")
            let second=try await value.favoriteImage(2,image:"image")
            try expect(first==cached && second != first && requests==2,"image cache missed or crossed favorite IDs")
            try await value.deleteFavorite(1)
            _ = try await value.favoriteImage(1,image:"image")
            try expect(requests==3,"removed favorite kept its cached image")
            _ = try await value.favoriteImage(1,image:"image",retry:true)
            try expect(requests==4,"image retry reused the failed cached data")
        }
        try await run("favorite image cache rejects cancelled and previous-account responses") {
            for logout in [false,true] {
                let api=FakeAPI(),value=await store(api:api)
                var release:CheckedContinuation<Data,Never>?
                api.favoriteImageHook={_,_ in await withCheckedContinuation {release=$0}}
                let task=Task {try await value.favoriteImage(1,image:"image")}
                while release==nil {await Task.yield()}
                if logout {await value.logout()} else {task.cancel()}
                release!.resume(returning:Data([1]))
                do {_ = try await task.value;throw NativeError(message:"late favorite picture was accepted")}
                catch is CancellationError {}
                if !logout {
                    api.favoriteImageHook={_,_ in Data([2])}
                    try expect(try await value.favoriteImage(1,image:"image")==Data([2]),"cancelled response populated the cache")
                }
            }
        }
        try await run("quote drafts follow their conversation and cancel preserves typed content") {
            let value=await store(),original=messageFixture(7)
            value.draft="我正在输入";value.quoteMessage(original)
            try expect(value.quotedMessage?.id==7,"quote was not selected")
            value.select("group:another");try expect(value.quotedMessage==nil,"quote crossed conversations")
            value.select("home:user-1");try expect(value.quotedMessage?.id==7 && value.draft=="我正在输入","quote or draft disappeared")
            value.cancelQuote();try expect(value.quotedMessage==nil && value.draft=="我正在输入","cancel changed draft")
        }
        try await run("offline quote snapshots persist with the same retry identifier") {
            let api=FakeAPI(),disk=MemoryDisk(),value=await store(disk,api:api)
            api.sendHook={_ in throw NativeError(message:"offline")}
            value.quoteMessage(messageFixture(8));value.draft="请解释";await value.sendDraft();await settle(value)
            try expect(value.quotedMessage==nil && value.pending.count==1,"quote did not move to outbox")
            let outgoing=value.pending[0]
            try expect(outgoing.quoteMessageId==8 && outgoing.quote?.text=="hello","outbox quote incomplete")
            let reopened=await store(disk,api:api)
            try expect(reopened.pending.first?.id==outgoing.id && reopened.pending.first?.quoteMessageId==8,"retry lost quote or identity")
            reopened.quoteMessage(messageFixture(8));try await reopened.clearLocal("home:user-1",revision:2)
            try expect(reopened.pending.isEmpty && reopened.quotedMessage==nil,"clear kept a stale reference")
        }
        try await run("quoted send checks server capability and never trusts a client snapshot") {
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ContractTransport.self]
            let api=MessageAPI(base:URL(string:"https://collection.invalid")!,token:"chat_fixture",configuration:config)
            var outgoing=Outgoing(clientMessageId:"client",deviceId:"device",sender:"Alice",platform:"ios",text:"回复",conversationId:"home:user-1")
            outgoing.quoteMessageId=7;outgoing.quote=MessageQuote(message:messageFixture(7));var posts=0
            ContractTransport.install {request in
                if request.url!.path.hasSuffix("/features") {return (404,Data("{}".utf8))}
                posts+=1;throw NativeError(message:"unexpected POST")
            }
            do {_ = try await api.send(outgoing);throw NativeError(message:"old server accepted quote")}
            catch let error as NativeError {try expect(error.message.contains("升级"),"missing upgrade feedback")}
            try expect(posts==0,"quote silently sent as plain text")
            ContractTransport.install {request in
                if request.url!.path.hasSuffix("/features") {return (200,Data(#"{"quotes":true,"favorites":true}"#.utf8))}
                let body=try collectionBody(request)
                try self.expect(body["quote"]==nil && body["quoteMessageId"] as? Int==7,"snapshot was sent as trusted source")
                return (200,try JSONEncoder().encode(messageFixture(9)))
            }
            _ = try await api.send(outgoing)
        }
        try await run("favorite HTTP endpoints preserve account auth and encoded literal query") {
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ContractTransport.self]
            let api=MessageAPI(base:URL(string:"https://collection.invalid")!,token:"chat_fixture",configuration:config)
            let item=FavoriteItem(id:12,message:messageFixture(7),conversationName:"项目群",savedAt:1000)
            ContractTransport.install {request in
                try self.expect(request.value(forHTTPHeaderField:"Authorization")=="Bearer chat_fixture","favorite request is unauthenticated")
                switch request.url!.path {
                case "/api/device-messages/7/favorite":try self.expect(request.httpMethod=="POST","favorite method");return (200,try JSONEncoder().encode(item))
                case "/api/device-messages/favorites":
                    let query=Dictionary(uniqueKeysWithValues:URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.map {($0.name,$0.value!)})
                    try self.expect(query==["q":"中文 %_&+","before":"20"],"favorite query changed")
                    return (200,try JSONEncoder().encode(FavoritePage(results:[item],hasMore:false,nextBefore:nil)))
                case "/api/device-messages/favorites/12/remove":try self.expect(request.httpMethod=="POST","remove method");return (200,Data(#"{"removed":true}"#.utf8))
                case "/api/device-messages/favorites/12/images/11111111-1111-4111-8111-111111111111":return (200,Data([1,2,3]))
                default:throw NativeError(message:"Unexpected favorite request")
                }
            }
            try expect(try await api.addFavorite(7).id==12,"favorite result")
            try expect(try await api.favorites(query:"中文 %_&+",before:20).results.first?.message.id==7,"favorite page result")
            try await api.removeFavorite(12)
            try expect(try await api.favoriteImage(12,image:"11111111-1111-4111-8111-111111111111")==Data([1,2,3]),"favorite image body")
        }
        try await run("favorite browser rejects delayed queries and retains cards on failed removal") {
            let old=FavoriteItem(id:1,message:messageFixture(7),conversationName:"Old",savedAt:1),fresh=FavoriteItem(id:2,message:messageFixture(8),conversationName:"New",savedAt:2)
            var release:CheckedContinuation<FavoritePage,Never>?
            let model=FavoriteBrowserState(fetch:{query,_ in
                if query=="old" {return await withCheckedContinuation {release=$0}}
                return FavoritePage(results:[fresh],hasMore:false,nextBefore:nil)
            },remove:{_ in throw NativeError(message:"offline")})
            model.query="old";model.reload();while release==nil {await Task.yield()}
            model.query="new";model.reload();while model.busy {await Task.yield()}
            release!.resume(returning:FavoritePage(results:[old],hasMore:false,nextBefore:nil));for _ in 0..<10 {await Task.yield()}
            try expect(model.items.map(\.id)==[2],"stale collection query escaped")
            let removed=await model.delete(fresh);try expect(!removed && model.items.map(\.id)==[2] && model.error != nil,"failed removal lost the saved card")
        }
    }
}

private func collectionBody(_ request:URLRequest) throws -> [String:Any] {
    var data=request.httpBody ?? Data()
    if data.isEmpty,let input=request.httpBodyStream {
        input.open();defer{input.close()};var buffer=[UInt8](repeating:0,count:4096)
        while input.hasBytesAvailable {let count=input.read(&buffer,maxLength:buffer.count);guard count>=0 else {throw NativeError(message:"request stream failed")};if count==0 {break};data.append(contentsOf:buffer.prefix(count))}
    }
    return try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
}

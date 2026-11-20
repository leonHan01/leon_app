import Foundation

@MainActor
extension Checks {
    func checkSearch() async throws {
        try await run("search HTTP encodes literal Chinese punctuation and scopes, without exposing credentials") {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ContractTransport.self]
            let api = MessageAPI(base: URL(string:"https://search.invalid")!, token:"chat_search_fixture", configuration:config)
            ContractTransport.install { request in
                guard request.httpMethod == "GET", request.value(forHTTPHeaderField:"Authorization") == "Bearer chat_search_fixture" else {throw NativeError(message:"search authentication")}
                let url = request.url!,items = Dictionary(uniqueKeysWithValues:URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.map {($0.name,$0.value!)})
                guard !url.absoluteString.contains("chat_search_fixture") else {throw NativeError(message:"token in URL")}
                if url.path == "/api/device-messages/search" {
                    guard items["q"] == "中文 %_&+?#", items["conversationId"] == "thread:one", items["before"] == "55" else {throw NativeError(message:"literal search encoding")}
                    return (200, Data(#"{"results":[],"hasMore":true,"nextBefore":25}"#.utf8))
                }
                guard url.path == "/api/device-messages/context", items["messageId"] == "44", items["direction"] == "before", items["conversationId"] == "thread:one" else {throw NativeError(message:"context anchor encoding")}
                return (200, Data(#"{"messages":[],"hasOlder":false,"hasNewer":true,"historyRevision":3}"#.utf8))
            }
            let page = try await api.search(query:"中文 %_&+?#",room:"thread:one",before:55)
            try expect(page.hasMore && page.nextBefore == 25,"lost search cursor")
            let context = try await api.searchContext(room:"thread:one",message:44,direction:"before")
            try expect(context.hasNewer && context.historyRevision == 3,"lost history metadata")
            ContractTransport.install { request in
                let items = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
                guard items.map(\.name) == ["q"] else {throw NativeError(message:"global search accidentally scoped")}
                return (404,Data("{}".utf8))
            }
            do {_ = try await api.search(query:"missing",room:nil,before:nil);throw NativeError(message:"old server accepted")}
            catch let error as NativeError {try expect(error.status == 404 && error.message.contains("升级"),"missing upgrade hint")}
        }
        try await run("search excerpts retain a distant match and emoji safely") {
            let body = String(repeating:"😀前文",count:80)+"关键字"+String(repeating:"后文",count:100)
            let excerpt = SearchExcerpt.text(body,query:"关键字")
            try expect(excerpt.contains("关键字") && excerpt.hasPrefix("…") && excerpt.hasSuffix("…"),"match lost outside first 120 characters")
            try expect(SearchExcerpt.text("Alpha\nBeta",query:"beta").contains("Beta"),"case-insensitive excerpt failed")
        }
        try await run("cancelled old queries cannot overwrite new search results") {
            let old = ChatSearchHit(message:messageFixture(1),conversationName:"Old"),fresh = ChatSearchHit(message:messageFixture(2),conversationName:"Fresh")
            var release: CheckedContinuation<ChatSearchPage,Never>?
            let search = ChatSearchState(room:nil) {query,_,_ in
                if query == "old" {return await withCheckedContinuation {release = $0}}
                return ChatSearchPage(results:[fresh],hasMore:false,nextBefore:nil)
            }
            search.query = "old";search.changed(immediate:true)
            while release == nil {await Task.yield()}
            search.query = "new";search.changed(immediate:true)
            while search.busy {await Task.yield()}
            release!.resume(returning:ChatSearchPage(results:[old],hasMore:true,nextBefore:1))
            for _ in 0..<10 {await Task.yield()}
            try expect(search.results.map(\.id) == [2] && !search.hasMore,"late result replaced active query")
            search.query = "";search.changed();try expect(search.results.isEmpty && !search.searched,"clear kept old messages")
        }
        try await run("search rejects old-account responses and expires revoked sessions") {
            let api = FakeAPI(),value = await store(api:api)
            var release:CheckedContinuation<ChatSearchPage,Never>?
            api.searchHook = {_,_,_ in await withCheckedContinuation {release = $0}}
            let pending = Task {() -> Bool in
                do {_ = try await value.searchMessages(query:"hello",room:nil,before:nil);return false}
                catch is CancellationError {return true}
                catch {return false}
            }
            while release == nil {await Task.yield()}
            await value.logout()
            release!.resume(returning:ChatSearchPage(results:[ChatSearchHit(message:messageFixture(1),conversationName:"old")],hasMore:false,nextBefore:nil))
            try expect(await pending.value,"old-account search escaped isolation")
            let expired = FakeAPI(),credentials = MemoryCredentials(),other = await store(api:expired,credentials:credentials)
            expired.searchHook = {_,_,_ in throw NativeError(message:"expired",status:401)}
            do {_ = try await other.searchMessages(query:"hello",room:nil,before:nil)} catch {}
            let saved = await credentials.read()
            try expect(!other.loggedIn && other.user == nil && saved == nil,"search 401 retained account or token")
        }
        try await run("search pagination preserves results on failure and retries the same cursor") {
            var calls = 0;var cursors:[Int64?] = []
            let hit = ChatSearchHit(message:messageFixture(20),conversationName:"Room"),older = ChatSearchHit(message:messageFixture(10),conversationName:"Room")
            let search = ChatSearchState(room:"home:user-1") {_,room,cursor in
                try self.expect(room == "home:user-1","lost conversation scope");calls += 1;cursors.append(cursor)
                if calls == 1 {return ChatSearchPage(results:[hit],hasMore:true,nextBefore:20)}
                if calls == 2 {throw NativeError(message:"offline")}
                return ChatSearchPage(results:[hit,older],hasMore:false,nextBefore:nil)
            }
            search.query = "hello";search.changed(immediate:true);while search.busy {await Task.yield()}
            search.more();while search.busy {await Task.yield()}
            try expect(search.results.map(\.id) == [20] && search.error != nil,"failure erased results")
            search.retry();while search.busy {await Task.yield()}
            try expect(search.results.map(\.id) == [20,10] && cursors == [nil,20,20],"retry skipped cursor or duplicated results")
        }
        try await run("original history loads both directions and discards cleared history") {
            let hit = ChatSearchHit(message:messageFixture(4),conversationName:"Room")
            var revision:Int64 = 1
            let history = ChatSearchHistory(hit:hit) {_,anchor,direction in
                let ids:[Int64] = direction == "around" ? [3,4,5] : direction == "before" ? [1,2] : [6,7]
                try self.expect(anchor == (direction == "before" ? 3 : direction == "after" ? 5 : 4),"wrong context paging anchor")
                return ChatSearchContext(messages:ids.map {messageFixture($0)},hasOlder:direction != "before",hasNewer:direction != "after",historyRevision:revision)
            }
            await history.load();await history.load("before");await history.load("after")
            try expect(history.messages.map(\.id) == [1,2,3,4,5,6,7] && !history.hasOlder && !history.hasNewer,"history order or flags")
            revision = 2;await history.load()
            try expect(history.messages.map(\.id) == [3,4,5],"explicit re-anchor did not refresh")
            revision = 3;await history.load("before")
            try expect(history.messages.isEmpty && history.error != nil,"remote clearing revived stale history")
        }
    }
}

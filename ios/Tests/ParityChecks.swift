import Foundation

private actor DelayedPicture {
    private var continuation:CheckedContinuation<Data,Never>?
    var started:Bool {continuation != nil}
    func load() async -> Data {await withCheckedContinuation {continuation = $0}}
    func finish() {continuation?.resume(returning:Data([9,8,7]));continuation = nil}
}
@MainActor
extension Checks {
    func checkParity() async throws {
        try await run("Only custom group owners can invite users and Agents") {
            let value = await store();value.user = ChatUser(id:"owner",username:"Alice")
            let room = Conversation(id:"group:owned",name:"项目群",kind:"group",agentId:nil,agentIds:[],ownerId:"owner")
            try expect(value.managesGroup(room),"owner cannot manage custom group")
            value.user = ChatUser(id:"member",username:"Bob")
            try expect(!value.managesGroup(room),"ordinary member can manage group")
            value.user = ChatUser(id:"owner",username:"Leon")
            for room in [Conversation(id:"shared",name:"设备群聊",kind:"group",agentId:nil,agentIds:[],ownerId:"owner"),Conversation(id:"home:owner",name:"设备群聊",kind:"group",agentId:nil,agentIds:[],ownerId:"owner"),Conversation(id:"direct:agent",name:"私聊",kind:"direct",agentId:"agent",agentIds:["agent"],ownerId:"owner")] {
                try expect(!value.managesGroup(room),"personal or direct chat allows invitations")
            }
        }
        try await run("Android legacy group ownership accepts missing and empty owners") {
            let value = await store();value.user = ChatUser(id:"owner",username:"Leon")
            for owner in [nil,""] as [String?] {
                let room = Conversation(id:"group:legacy",name:"旧群聊",kind:"group",agentId:nil,agentIds:[],ownerId:owner)
                try expect(value.owns(room),"legacy owner cannot invite group members")
                value.user = ChatUser(id:"visitor",username:"Alice")
                try expect(!value.owns(room),"ordinary user became legacy group owner")
                value.user = ChatUser(id:"owner",username:"Leon")
            }
        }
        try await run("Android connection isolation rejects late pictures and avatars after logout") {
            for avatar in [false,true] {
                let api = FakeAPI(),value = await store(api:api),gate = DelayedPicture()
                api.imageHook = {_ in await gate.load()};api.avatarHook = {_ in await gate.load()}
                let task = Task {() -> Result<Data,Error> in
                    do {return .success(try await (avatar ? value.avatarData("alfred") : value.imageData(UUID().uuidString)))}
                    catch {return .failure(error)}
                }
                for _ in 0..<1000 {if await gate.started {break};await Task.yield()}
                try expect(await gate.started,"image request did not start")
                await value.logout();await gate.finish()
                if case .success = await task.value {throw NativeError(message:"previous account image returned to the new screen")}
            }
        }
    }
}

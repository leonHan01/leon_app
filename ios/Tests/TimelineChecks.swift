import Foundation
import Combine

@MainActor
extension Checks {
    private func timedMessage(_ id:Int64,_ time:Int64) -> Message {
        Message(id:id,clientMessageId:"timeline-\(id)",deviceId:"device",sender:"Alice",platform:"ios",text:"hello",createdAt:time,conversationId:"shared",role:"user",agentId:nil,replyTo:nil,images:[],userId:nil)
    }
    func checkTimeline() async throws {
        try await run("empty pages stay quiet and metadata-only pages update the timeline") {
            let value=await store(api:FakeAPI()),room=value.roomID
            let initial = MessagePage(messages:[timedMessage(20,1_000)],hasMore:true,jobs:[],contextOperations:[],historyRevision:1)
            _ = try await value.apply(initial,room:room,older:false)
            _ = value.timeline
            var publications = 0
            let subscription = value.objectWillChange.sink { publications += 1 }
            defer { subscription.cancel() }
            _ = try await value.apply(pageFixture([]),room:room,older:false)
            try expect(publications == 0 && value.room.hasOlder,"empty poll changed the view or older-page availability")
            let job = AgentJob(messageId:20,agentId:"a",agentName:"A",status:"RUNNING",error:"")
            _ = try await value.apply(pageFixture([],jobs:[job]),room:room,older:false)
            try expect(publications == 1 && value.timeline.entries.contains {$0.id == "job:20:a"},"empty message page lost its job update")
            _ = try await value.apply(pageFixture([timedMessage(10,500)],jobs:[job]),room:room,older:true)
            _ = try await value.apply(pageFixture([timedMessage(30,1_500)],jobs:[job]),room:room,older:false)
            try expect(value.timeline.messageIDs == [10,20,30] && !value.room.hasOlder,"prepend and append broke message order or pagination")
            let publicationsBeforeOverlap = publications
            _ = try await value.apply(pageFixture([timedMessage(20,1_000)],jobs:[job]),room:room,older:false)
            try expect(publications == publicationsBeforeOverlap,"identical overlapping page republished the timeline")
        }

        try await run("cached history keeps the reading anchor and clears positions with history") {
            let value=await store(api:FakeAPI()),room=value.roomID
            value.room.messages=(1...500).map {messageFixture(Int64($0))};value.room.loaded=true
            value.scrollPositions[room]=ConversationScrollPosition(offset:500,messageID:20,messageTop:-10)
            value.select("group:other");value.select(room)
            try expect(value.room.messages.count==300 && value.room.messages.contains {$0.id==20},"room cache discarded the reading anchor")
            try await value.clearLocal(room,revision:2)
            try expect(value.scrollPositions[room]==nil,"cleared history retained a stale reading position")
        }

        try await run("Android timeline keeps jobs and context notices next to their triggers") {
            let messages = [timedMessage(10,1_000_000),timedMessage(20,1_100_000)]
            let jobs = [AgentJob(messageId:20,agentId:"b",agentName:"B",status:"FAILED",error:"offline"),AgentJob(messageId:10,agentId:"a",agentName:"A",status:"RUNNING",error:"")]
            let operation = ContextOperation(id:"compact",agentId:"a",agentName:"A",status:"RUNNING",error:"",result:"",createdAt:1_050_000,kind:"COMPACT")
            let entries = ChatTimeline.entries(messages:messages,jobs:jobs,operations:[operation])
            try expect(entries.map(\.id) == ["time:10","message:10","job:10:a","operation:compact","message:20","job:20:b"],"notices detached from their triggering messages")
            try expect(Set(entries.map(\.id)).count == entries.count,"duplicate timeline identities")
        }
        try await run("Android five-minute time labels preserve the boundary and calendar order") {
            let entries = ChatTimeline.entries(messages:[timedMessage(1,1_000_000),timedMessage(2,1_300_000),timedMessage(3,1_300_001)],jobs:[],operations:[])
            let labels = entries.compactMap {entry -> Int64? in if case .time(let id,_) = entry {return id};return nil}
            try expect(labels == [1,3],"time labels added to every bubble or five-minute boundary changed")
        }
    }
}

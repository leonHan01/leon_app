import Foundation

@MainActor
extension Checks {
    private func timedMessage(_ id:Int64,_ time:Int64) -> Message {
        Message(id:id,clientMessageId:"timeline-\(id)",deviceId:"device",sender:"Alice",platform:"ios",text:"hello",createdAt:time,conversationId:"shared",role:"user",agentId:nil,replyTo:nil,images:[],userId:nil)
    }
    func checkTimeline() async throws {
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

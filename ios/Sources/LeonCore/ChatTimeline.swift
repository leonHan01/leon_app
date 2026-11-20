import Foundation

// The Android timeline interleaves job notices by triggering message and context
// operations by creation time. Time labels appear only across five-minute gaps.
enum ChatTimeline {
    enum Entry: Identifiable {
        case time(messageID:Int64,timestamp:Int64)
        case message(Message)
        case job(AgentJob)
        case operation(ContextOperation)
        var id: String {
            switch self {
            case .time(let id,_):return "time:\(id)"
            case .message(let value):return "message:\(value.id)"
            case .job(let value):return "job:\(value.id)"
            case .operation(let value):return "operation:\(value.id)"
            }
        }
    }
    static func entries(messages:[Message],jobs:[AgentJob],operations:[ContextOperation]) -> [Entry] {
        let jobs = jobs.sorted {$0.messageId < $1.messageId}
        let operations = operations.sorted {($0.createdAt>0 ? $0.createdAt : .max) < ($1.createdAt>0 ? $1.createdAt : .max)}
        var result:[Entry] = [],jobIndex = 0,operationIndex = 0,lastTime:Int64?
        for message in messages {
            while jobIndex<jobs.count && jobs[jobIndex].messageId<message.id {result.append(.job(jobs[jobIndex]));jobIndex += 1}
            while operationIndex<operations.count && operations[operationIndex].createdAt>0 && operations[operationIndex].createdAt<=message.createdAt {
                result.append(.operation(operations[operationIndex]));operationIndex += 1
            }
            if lastTime == nil || abs(message.createdAt-lastTime!)>300_000 {result.append(.time(messageID:message.id,timestamp:message.createdAt));lastTime = message.createdAt}
            result.append(.message(message))
            while jobIndex<jobs.count && jobs[jobIndex].messageId==message.id {result.append(.job(jobs[jobIndex]));jobIndex += 1}
        }
        result += operations.dropFirst(operationIndex).map(Entry.operation)
        result += jobs.dropFirst(jobIndex).map(Entry.job)
        return result
    }
}

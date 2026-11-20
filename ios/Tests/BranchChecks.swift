import Foundation

@MainActor
extension Checks {
    func checkBranches() async throws {
        try await run("branch creation preserves drafts and only adds the returned conversation") {
            let api=FakeAPI(),value=await store(api:api)
            value.draft="原会话草稿";value.quoteMessage(messageFixture(7))
            let created=Conversation(id:"branch:copy",name:"方案 B",kind:"direct",agentId:"agent",agentIds:["agent"])
            api.branchHook={room,message,name,request in
                try self.expect(room=="home:user-1" && message==7 && name=="方案 B" && request=="stable-request","branch coordinates or identity changed")
                return created
            }
            value.beginBranch(messageFixture(7))
            try expect(value.branchMessage?.id==7,"branch menu lost the selected message")
            _ = try await value.createBranch(messageFixture(7),name:"方案 B",requestId:"stable-request")
            try expect(value.conversations.contains(where:{$0.id==created.id}),"branch absent from directory")
            try expect(value.roomID=="home:user-1" && value.draft=="原会话草稿" && value.quotedMessage?.id==7,"creating a branch changed the source draft or navigation")
            value.select(created.id);try expect(value.draft.isEmpty && value.quotedMessage==nil,"branch inherited an unsent draft")
            value.select("home:user-1");try expect(value.draft=="原会话草稿" && value.quotedMessage?.id==7,"source draft was lost")
        }
        try await run("failed branch creation retries the same request without dropping the source draft") {
            let api=FakeAPI(),value=await store(api:api);value.draft="保留"
            var calls=0
            api.branchHook={_,_,_,request in
                calls+=1;try self.expect(request=="same-request","retry changed its identity")
                if calls==1 {throw NativeError(message:"offline")}
                return Conversation(id:"branch:retry",name:"分支",kind:"group",agentId:nil,agentIds:[])
            }
            do {_ = try await value.createBranch(messageFixture(7),name:"分支",requestId:"same-request");throw NativeError(message:"failure was accepted")}
            catch let failure as NativeError {try expect(failure.message=="offline","request failure was hidden")}
            try expect(value.conversations.isEmpty && value.draft=="保留","failed request changed source state")
            _ = try await value.createBranch(messageFixture(7),name:"分支",requestId:"same-request")
            try expect(calls==2 && value.conversations.count==1,"retry lost the branch")
        }
        try await run("branch creation rejects cancelled and previous-account responses") {
            for logout in [false,true] {
                let api=FakeAPI(),value=await store(api:api)
                var release:CheckedContinuation<Conversation,Never>?
                api.branchHook={_,_,_,_ in await withCheckedContinuation {release=$0}}
                let task=Task {try await value.createBranch(messageFixture(7),name:"分支",requestId:"request")}
                while release==nil {await Task.yield()}
                if logout {await value.logout()} else {task.cancel()}
                release!.resume(returning:Conversation(id:"branch:old",name:"旧账号",kind:"group",agentId:nil,agentIds:[]))
                do {_ = try await task.value;throw NativeError(message:"late response was accepted")}
                catch is CancellationError {}
                try expect(value.conversations.isEmpty,"late branch crossed accounts or cancellation")
            }
        }
        try await run("branch HTTP uses authenticated POST with coordinates and returns upgrade feedback") {
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ContractTransport.self]
            let api=MessageAPI(base:URL(string:"https://branch.invalid")!,token:"chat_fixture",configuration:config)
            let created=Conversation(id:"branch:result",name:"分支",kind:"group",agentId:nil,agentIds:[])
            ContractTransport.install {request in
                try self.expect(request.httpMethod=="POST" && request.url!.path=="/api/conversations/dm:user:agent/branches","branch path or method incorrect")
                try self.expect(request.value(forHTTPHeaderField:"Authorization")=="Bearer chat_fixture","branch lost authentication")
                var data=request.httpBody ?? Data()
                if data.isEmpty,let input=request.httpBodyStream {
                    input.open();defer {input.close()};var buffer=[UInt8](repeating:0,count:4096)
                    while input.hasBytesAvailable {let n=input.read(&buffer,maxLength:buffer.count);if n<=0 {break};data.append(contentsOf:buffer.prefix(n))}
                }
                let body=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                try self.expect(body.count==3 && body["messageId"] as? Int==7 && body["name"] as? String=="分支" && body["requestId"] as? String=="request","branch trusted client history or lost coordinates")
                return (200,try JSONEncoder().encode(created))
            }
            try expect(try await api.branch(room:"dm:user:agent",message:7,name:"分支",requestId:"request").id==created.id,"branch response lost")
            ContractTransport.install {_ in (404,Data("{}".utf8))}
            do {_ = try await api.branch(room:"shared",message:7,name:"分支",requestId:"request");throw NativeError(message:"old server accepted branch")}
            catch let error as NativeError {try expect(error.message.contains("升级"),"old server lacks upgrade feedback")}
            do {_ = try await api.branch(room:"../admin",message:7,name:"分支",requestId:"request");throw NativeError(message:"path accepted")}
            catch let error as NativeError {try expect(error.message.contains("标识"),"invalid source path not rejected locally")}
        }
    }
}

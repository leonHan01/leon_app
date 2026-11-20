import Foundation

@MainActor
extension Checks {
    func checkDocuments() async throws {
        try await run("document imports validate formats and disk outbox preserves original bytes") {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
            let content=Data("月份,营收\n十一月,100".utf8)
            for ext in DraftDocument.extensions {
                let url=folder.appendingPathComponent("报告."+ext);try content.write(to:url)
                let doc=try DraftDocument.read(url)
                try expect(doc.data==content && doc.attachment.name==url.lastPathComponent,"import changed the original file")
            }
            let bad=folder.appendingPathComponent("run.exe");try content.write(to:bad)
            do {_ = try DraftDocument.read(bad);throw NativeError(message:"unsupported file accepted")}catch is DocumentError {}
            let empty=folder.appendingPathComponent("empty.csv");try Data().write(to:empty)
            do {_ = try DraftDocument.read(empty);throw NativeError(message:"empty document accepted")}catch is DocumentError {}
            let doc=try DraftDocument.read(folder.appendingPathComponent("报告.csv")),scope=String(repeating:"a",count:64)
            let disk=FilePersistence(root:folder.appendingPathComponent("disk"));try await disk.saveDocument(doc,scope:scope)
            try expect(try await disk.document(doc.id,scope:scope)==content,"document bytes were not durable")
            try expect(try await disk.document(doc.id,scope:String(repeating:"b",count:64))==nil,"document crossed account scope")
            try await disk.removeDocuments([doc.id],scope:scope)
            try expect(try await disk.document(doc.id,scope:scope)==nil,"document remained after outbox cleanup")
        }
        try await run("document-only drafts persist before upload and follow their conversation") {
            let api=FakeAPI(),value=await store(api:api),room=value.roomID
            let doc=DraftDocument(attachment:DocumentAttachment(id:UUID().uuidString.lowercased(),name:"report.csv",mimeType:"text/csv",byteCount:3,characterCount:0,truncated:false),data:Data([1,2,3]))
            value.draftDocuments=[doc];try expect(value.canSend,"document-only message cannot be sent")
            value.select("group:other");try expect(value.draftDocuments.isEmpty,"document leaked into another room")
            value.select(room);try expect(value.draftDocuments==[doc],"document draft was discarded")
            await value.sendDraft()
            for _ in 0..<30 {await Task.yield()}
            try expect(value.pending.count==1 && value.pending[0].documentIds==[doc.id],"failed upload lost durable document reference")
            try expect(value.draftDocuments.isEmpty,"queued document stayed in composer")
            try await value.clearLocal(room,revision:2);try expect(value.pending.isEmpty,"clear retained a stale document message")
        }
        try await run("document HTTP preserves filenames, authorization, raw bytes and metadata isolation") {
            let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[ContractTransport.self]
            let api=MessageAPI(base:URL(string:"https://contract.invalid")!,token:"chat_documents",configuration:configuration)
            let doc=DocumentAttachment(id:UUID().uuidString.lowercased(),name:"销售 %&+.csv",mimeType:"text/csv",byteCount:4,characterCount:0,truncated:false)
            var paths:[String]=[]
            ContractTransport.install {request in
                try self.expect(request.value(forHTTPHeaderField:"Authorization")=="Bearer chat_documents","document endpoint omitted authorization")
                let url=request.url!;paths.append(url.path)
                if url.path=="/api/device-messages/documents" {
                    let query=URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!
                    try self.expect(query.first {$0.name=="name"}?.value==doc.name,"filename encoding changed")
                    try self.expect(request.httpMethod=="POST","document upload was not POST")
                    return (200,try JSONEncoder().encode(doc))
                }
                if url.path=="/api/device-messages" {
                    var data=request.httpBody ?? Data()
                    if data.isEmpty,let input=request.httpBodyStream {input.open();defer {input.close()};var buffer=[UInt8](repeating:0,count:4096);while input.hasBytesAvailable {let n=input.read(&buffer,maxLength:buffer.count);if n<=0 {break};data.append(contentsOf:buffer.prefix(n))}}
                    let body=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                    try self.expect(body["documentIds"] as? [String]==[doc.id] && body["documents"]==nil,"client document snapshot was trusted")
                    return (200,try JSONEncoder().encode(messageFixture(1)))
                }
                return (200,Data([1,2,3,4]))
            }
            try await api.uploadDocument(doc,room:"thread:one",data:Data([1,2,3,4]))
            _ = try await api.document(doc.id,favorite:nil);_ = try await api.document(doc.id,favorite:9)
            let out=Outgoing(clientMessageId:UUID().uuidString,deviceId:UUID().uuidString,sender:"Alice",platform:"ios",text:"分析",conversationId:"thread:one",documentIds:[doc.id],documents:[doc])
            _ = try await api.send(out)
            try expect(paths.contains("/api/device-messages/favorites/9/documents/"+doc.id),"favorite original used the chat endpoint")
        }
    }
}

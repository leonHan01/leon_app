import Foundation

@main
struct ArchiveChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leon-archive-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try LeonBlogExporter.destination(root: directory.appendingPathComponent("library").path)
        let id = UUID().uuidString.lowercased(), imageId = UUID().uuidString.lowercased()
        let image = directory.appendingPathComponent("image.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4ZkAAAAASUVORK5CYII=")!.write(to: image)
        let operation = ContextOperation(id: id, agentId: "agent", agentName: "Sol", status: "SUCCEEDED", error: "", result: "ok", createdAt: 1, kind: "ARCHIVE")
        var message = Message(id: 1, clientMessageId: "client", deviceId: "device", sender: "用户", platform: "macos", text: "原始对话 <script>不能执行</script>\n第二行", createdAt: 1700000000123, conversationId: "room", role: "user", agentId: nil, replyTo: nil)
        message.images = [ChatImage(id: imageId, mimeType: "image/png", width: 1, height: 1, byteCount: 68)]
        let archive = ChatArchive(id: id, title: "临时对话归档验收", summary: "首先展示的 AI 总结", conversationId: "room", throughId: 1, operation: operation, messages: [message])
        let first = try LeonBlogExporter.export(archive, destination: destination, imageFiles: [imageId: image])
        let second = try LeonBlogExporter.export(archive, destination: destination, imageFiles: [:])
        precondition(first.slug == second.slug)
        let process = Process();process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/leonbook")
        process.arguments = ["articles.get", "--root", destination.root, "--user", destination.user, "--json", "{\"slug\":\"" + first.slug + "\"}"]
        let output = Pipe();process.standardOutput = output;try process.run();let data = output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any], article = envelope["result"] as! [String: Any]
        let body = article["body"] as! String
        precondition(article["status"] as? String == "draft")
        precondition(body.range(of: "对话总结")!.lowerBound < body.range(of: "原始对话")!.lowerBound)
        precondition(body.contains("第二行") && body.contains("&lt;script&gt;") && !body.contains("<script>不能执行"))
        precondition((article["media"] as! [Any]).count == 2)
        print("PASS: real LeonBook CLI exports summary-first draft, exact text, copied image and original attachment; repeat export reuses saved article")
        print("PASS: isolated temporary library only; real user library unchanged")
    }
}

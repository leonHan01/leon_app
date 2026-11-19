import Foundation

enum LeonBlogExporter {
    struct Destination: Codable, Sendable { let root: String; let user: String }
    struct Saved: Sendable { let slug: String; let title: String }
    private static func executable() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/leonbook").path] + (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin").split(separator: ":").map { String($0) + "/leonbook" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw ClientError.message("未找到 leonbook CLI，请先安装或配置 LeonBook。当前上下文已保留。") }
        return URL(fileURLWithPath: path)
    }
    static func destination(root: String? = nil) throws -> Destination {
        let value = try call("workspace.info", params: [:], destination: root.map { Destination(root: $0, user: "") })
        guard let root = value["root"] as? String, let user = (value["user"] as? [String: Any])?["id"] as? String,
              FileManager.default.fileExists(atPath: root), !user.isEmpty else { throw ClientError.message("无法读取 LeonBook 资料库，请确认磁盘已连接。") }
        return Destination(root: root, user: user)
    }
    private static func call(_ method: String, params: [String: Any], destination: Destination?, missingAllowed: Bool = false) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leonbook-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = directory.appendingPathComponent("request.json"), output = directory.appendingPathComponent("output.json"), errors = directory.appendingPathComponent("error.txt")
        let data = try JSONSerialization.data(withJSONObject: params)
        guard data.count < 8 * 1024 * 1024 else { throw ClientError.message("归档请求超过 CLI 限制，当前上下文已保留。") }
        try data.write(to: request, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: errors)
        defer { try? out.close(); try? err.close() }
        let process = Process(); process.executableURL = try executable()
        var arguments = [method]
        if let destination { arguments += ["--root", destination.root]; if !destination.user.isEmpty { arguments += ["--user", destination.user] } }
        process.arguments = arguments + ["--json", "@" + request.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = out; process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw ClientError.message("LeonBook CLI 响应超时，请重试核验归档；当前上下文已保留。") }
        let response = try Data(contentsOf: output)
        guard let envelope = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw ClientError.message("LeonBook CLI 返回格式无效，当前上下文已保留。") }
        if let failure = envelope["error"] as? [String: Any] {
            if missingAllowed, failure["code"] as? String == "not_found" { return [:] }
            throw ClientError.message("LeonBook：" + (failure["message"] as? String ?? "写入未完成"))
        }
        guard process.terminationStatus == 0, let result = envelope["result"] as? [String: Any] else { throw ClientError.message("LeonBook 未确认操作成功，当前上下文已保留。") }
        return result
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func export(_ archive: ChatArchive, destination: Destination, imageFiles: [String: URL]) throws -> Saved {
        let slug = "leon-chat-" + archive.id.lowercased()
        func verify(_ article: [String: Any]) throws -> Saved {
            let properties = article["properties"] as? [String: Any]
            guard article["slug"] as? String == slug,
                  (properties?["leonChatArchiveId"] as? [String: Any])?["value"] as? String == archive.id else {
                throw ClientError.message("LeonBook 已存在同名文章，归档标识不一致；未覆盖文章，当前上下文保留。")
            }
            return Saved(slug: slug, title: article["title"] as? String ?? archive.title)
        }
        let existing = try call("articles.get", params: ["slug": slug], destination: destination, missingAllowed: true)
        if !existing.isEmpty { return try verify(existing) }
        var media: [[String: Any]] = [], urls: [String: String] = [:]
        let imageIDs = Set(archive.messages.flatMap { ($0.images ?? []).map(\.id) })
        for id in imageIDs.sorted() {
            guard let file = imageFiles[id] else { throw ClientError.message("原对话图片未准备完整，当前上下文已保留。") }
            let item = try call("media.upload", params: ["path": file.path, "kind": "image", "slug": slug], destination: destination)
            guard let url = item["url"] as? String else { throw ClientError.message("LeonBook 未返回图片地址。") }
            urls[id] = url
            media.append(["kind": "image", "name": item["name"] as? String ?? id + ".jpg", "size": item["size"] as? Int ?? 0, "url": url])
        }
        var raw = "# " + archive.title + "\n\n", html = "<h2>原始对话</h2>"
        for message in archive.messages {
            let identity = message.sender + (message.role == "assistant" ? " · AI" : " · 用户")
            let date = message.date.ISO8601Format()
            raw += "\n## " + identity + " · " + date + "\n\n" + message.text + "\n"
            html += "<h3>" + escape(identity) + "</h3><p>" + escape(date) + "</p><pre>" + escape(message.text) + "</pre>"
            for image in message.images ?? [] {
                guard let url = urls[image.id] else { continue }
                raw += "\n![对话图片](" + url + ")\n"
                html += "<p><img src=\"" + escape(url) + "\" alt=\"原始对话图片\"></p>"
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leon-chat-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("原始对话.md"); try Data(raw.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let attachment = try call("media.upload", params: ["path": file.path, "kind": "file", "slug": slug], destination: destination)
        guard let originalURL = attachment["url"] as? String else { throw ClientError.message("原始对话附件未保存成功。") }
        media.append(["kind": "file", "name": "原始对话.md", "size": attachment["size"] as? Int ?? 0, "url": originalURL])
        let summary = "<h2>对话总结</h2>" + archive.summary.components(separatedBy: "\n").map { "<p>" + escape($0) + "</p>" }.joined()
        let download = "<p><a href=\"" + escape(originalURL) + "\">下载完整原始对话（Markdown）</a></p>"
        let properties: [String: Any] = ["leonChatArchiveId": ["kind": "text", "value": archive.id]]
        var params: [String: Any] = ["slug": slug, "title": archive.title, "body": summary + download + "<hr>" + html,
            "format": "html", "status": "draft", "category": "AI 对话", "tags": ["AI对话", "Leon聊天归档"], "properties": properties, "media": media]
        if try JSONSerialization.data(withJSONObject: params).count > 6 * 1024 * 1024 {
            params["body"] = summary + "<h2>原始对话</h2><p>本轮内容较长，完整原文已保存在附件中，所有图片均已复制到资料库。</p>" + download
        }
        _ = try call("articles.create", params: params, destination: destination)
        return try verify(call("articles.get", params: ["slug": slug], destination: destination))
    }
}

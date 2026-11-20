import Foundation
import CryptoKit

protocol Persistence: Sendable {
    func deviceID() async throws -> String
    func load(scope: String) async throws -> OutboxSnapshot
    func save(scope: String, snapshot: OutboxSnapshot) async throws
    func saveDocument(_ document:DraftDocument,scope:String) async throws
    func document(_ id:String,scope:String) async throws -> Data?
    func removeDocuments(_ ids:[String],scope:String) async throws
    func saveImage(_ image: DraftImage, scope: String) async throws
    func image(_ id: String, scope: String) async throws -> Data?
    func removeImages(_ ids: [String], scope: String) async throws
}
extension Persistence {
    func saveDocument(_ document:DraftDocument,scope:String) async throws {try await saveImage(DraftImage(id:document.id,data:document.data),scope:scope)}
    func document(_ id:String,scope:String) async throws -> Data? {try await image(id,scope:scope)}
    func removeDocuments(_ ids:[String],scope:String) async throws {try await removeImages(ids,scope:scope)}
}
protocol CredentialStorage: Sendable {
    func read() async throws -> Credentials?
    func save(_ credentials: Credentials?) async throws
}
func accountScope(server: String, userID: String) -> String {
    SHA256.hash(data: Data((server + "\n" + userID).utf8)).map { String(format:"%02x",$0) }.joined()
}
actor FilePersistence: Persistence {
    let root: URL
    init(root: URL) { self.root = root }
    static func application() throws -> FilePersistence {
        let root = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("LeonIOS",isDirectory:true)
        return FilePersistence(root:root)
    }
    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        #if os(iOS)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to:file,options:.atomic)
        #endif
    }
    func deviceID() throws -> String {
        let file = root.appendingPathComponent("device-id")
        if FileManager.default.fileExists(atPath:file.path) {
            let id = String(decoding:try Data(contentsOf:file),as:UTF8.self)
            guard UUID(uuidString:id) != nil else { throw NativeError(message:"设备标识已损坏，请恢复本地数据。") }; return id
        }
        let id = UUID().uuidString.lowercased(); try write(Data(id.utf8),to:file); return id
    }
    private func directory(_ scope: String) throws -> URL {
        guard scope.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw NativeError(message:"连接存储标识无效。") }
        return root.appendingPathComponent("accounts").appendingPathComponent(scope,isDirectory:true)
    }
    private func imageURL(_ id: String, scope: String) throws -> URL {
        guard UUID(uuidString:id) != nil else { throw NativeError(message:"图片标识无效。") }
        return try directory(scope).appendingPathComponent("images").appendingPathComponent(id+".jpg")
    }
    func load(scope: String) throws -> OutboxSnapshot {
        let file = try directory(scope).appendingPathComponent("outbox.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return OutboxSnapshot() }
        // A damaged queue must never be silently replaced by an empty one.
        return try JSONDecoder().decode(OutboxSnapshot.self,from:Data(contentsOf:file))
    }
    func save(scope: String, snapshot: OutboxSnapshot) throws {
        try write(JSONEncoder().encode(snapshot),to:directory(scope).appendingPathComponent("outbox.json"))
    }
    private func documentURL(_ id:String,scope:String)throws -> URL {
        guard UUID(uuidString:id) != nil else {throw NativeError(message:"文档标识无效。")}
        return try directory(scope).appendingPathComponent("documents").appendingPathComponent(id)
    }
    func saveDocument(_ document:DraftDocument,scope:String)throws {try write(document.data,to:documentURL(document.id,scope:scope))}
    func document(_ id:String,scope:String)throws -> Data? {let file=try documentURL(id,scope:scope);return FileManager.default.fileExists(atPath:file.path) ? try LocalFile.read(file,limit:10*1024*1024) : nil}
    func removeDocuments(_ ids:[String],scope:String)throws {for id in ids {let file=try documentURL(id,scope:scope);if FileManager.default.fileExists(atPath:file.path){try FileManager.default.removeItem(at:file)}}}
    func saveImage(_ image: DraftImage, scope: String) throws { try write(image.data,to:imageURL(image.id,scope:scope)) }
    func image(_ id: String, scope: String) throws -> Data? {
        let file = try imageURL(id,scope:scope)
        return FileManager.default.fileExists(atPath:file.path) ? try Data(contentsOf:file) : nil
    }
    func removeImages(_ ids: [String], scope: String) throws {
        for id in ids {
            let file = try imageURL(id,scope:scope)
            if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
        }
    }
}

enum LocalFile {
    static func read(_ url: URL, limit: Int) throws -> Data {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= limit else { throw NativeError(message:"所选文件过大。") }
        let file = try FileHandle(forReadingFrom:url); defer {try? file.close()}
        var result = Data()
        while let bytes = try file.read(upToCount:65536), !bytes.isEmpty {
            guard result.count+bytes.count <= limit else { throw NativeError(message:"所选文件过大。") }; result.append(bytes)
        }
        return result
    }
}

import Foundation
import zlib

struct BackupPreview {
    let name: String
    let kind: String
    let messageCount: Int
    static let maximumBytes = 32 * 1024 * 1024
    private static let maximumManifest = 16 * 1024 * 1024
    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw NativeError(message:"备份不能超过 32 MB。") }
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ width: Int) throws -> UInt32 {
            guard offset >= 0, offset + width <= bytes.count else { throw NativeError(message:"备份文件不完整。") }
            return (0..<width).reduce(0) { $0 | UInt32(bytes[offset+$1]) << UInt32(8*$1) }
        }
        var end: Int?
        guard bytes.count >= 22 else { throw NativeError(message:"不是 ZIP 备份。") }
        for position in stride(from:bytes.count-22,through:max(0,bytes.count-65557),by:-1) {
            if try number(position,4) == 0x06054b50, position+22+Int(try number(position+20,2)) == bytes.count { end = position; break }
        }
        guard let end, try number(end+4,2) == 0, try number(end+6,2) == 0 else { throw NativeError(message:"备份 ZIP 格式不受支持。") }
        let count = Int(try number(end+10,2)); var cursor = Int(try number(end+16,4))
        guard count > 0, count <= 65535, Int(try number(end+12,4)) <= bytes.count-cursor else { throw NativeError(message:"备份目录无效。") }
        var names = Set<String>(), total = 0
        var manifest: (offset:Int, compressed:Int, size:Int, method:UInt32, crc:UInt32)?
        for _ in 0..<count {
            guard try number(cursor,4) == 0x02014b50 else { throw NativeError(message:"备份目录已损坏。") }
            let flags = try number(cursor+8,2), method = try number(cursor+10,2)
            let compressed = Int(try number(cursor+20,4)), size = Int(try number(cursor+24,4))
            let length = Int(try number(cursor+28,2)), extra = Int(try number(cursor+30,2)), comment = Int(try number(cursor+32,2))
            let local = Int(try number(cursor+42,4)), start = cursor+46
            guard start+length <= bytes.count, let name = String(bytes:bytes[start..<start+length],encoding:.utf8), names.insert(name).inserted,
                  flags & 1 == 0, method == 0 || method == 8 else { throw NativeError(message:"备份包含重复、加密或无效文件。") }
            total += size
            guard total <= Self.maximumBytes+Self.maximumManifest else { throw NativeError(message:"备份展开后过大。") }
            if name == "manifest.json" {
                guard size <= Self.maximumManifest, try number(local,4) == 0x04034b50 else { throw NativeError(message:"备份清单无效。") }
                let payload = local+30+Int(try number(local+26,2))+Int(try number(local+28,2))
                guard payload >= 0, compressed <= bytes.count-payload else { throw NativeError(message:"备份清单不完整。") }
                manifest = (payload,compressed,size,method,try number(cursor+16,4))
            } else {
                guard (name.range(of:"^images/[a-f0-9-]{36}\\.jpg$",options:.regularExpression) != nil && size <= 1_048_576) || (name.range(of:"^documents/[a-f0-9-]{36}$",options:.regularExpression) != nil && size <= 10*1024*1024) else { throw NativeError(message:"备份文件结构无效。") }
            }
            cursor = start+length+extra+comment
        }
        guard let entry = manifest else { throw NativeError(message:"不是 Leon 聊天备份。") }
        let compressed = Data(bytes[entry.offset..<entry.offset+entry.compressed])
        let metadata = entry.method == 0 ? compressed : try Self.inflate(compressed)
        let checksum = metadata.withUnsafeBytes { buffer in crc32(0,buffer.bindMemory(to:Bytef.self).baseAddress,uInt(buffer.count)) }
        guard metadata.count == entry.size, UInt32(checksum) == entry.crc,
              let object = try JSONSerialization.jsonObject(with:metadata) as? [String:Any],
              object["format"] as? String == "leon-chat", [1,2].contains(object["version"] as? Int ?? 0),
              let room = object["conversation"] as? [String:Any], let name = room["name"] as? String,
              let kind = room["kind"] as? String, ["direct","group"].contains(kind),
              let messages = object["messages"] as? [Any], messages.count <= 10000
        else { throw NativeError(message:"备份损坏、格式不受支持或消息超过 10,000 条。") }
        self.name = name; self.kind = kind; self.messageCount = messages.count
    }
    private static func inflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream,-MAX_WBITS,ZLIB_VERSION,Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw NativeError(message:"无法读取压缩备份。") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating:input.bindMemory(to:Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var output = Data(), block = [UInt8](repeating:0,count:65536), code:Int32 = Z_OK
            repeat {
                let produced: Int = try block.withUnsafeMutableBytes { buffer in
                    stream.next_out = buffer.bindMemory(to:Bytef.self).baseAddress; stream.avail_out = uInt(buffer.count)
                    code = zlib.inflate(&stream,Z_NO_FLUSH)
                    guard code == Z_OK || code == Z_STREAM_END else { throw NativeError(message:"备份压缩数据无效。") }
                    return buffer.count-Int(stream.avail_out)
                }
                guard output.count+produced <= maximumManifest, produced > 0 || code == Z_STREAM_END else { throw NativeError(message:"备份清单过大或已损坏。") }
                output.append(contentsOf:block.prefix(produced))
            } while code != Z_STREAM_END
            return output
        }
    }
}

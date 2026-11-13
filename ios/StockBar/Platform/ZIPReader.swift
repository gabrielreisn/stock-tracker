import Foundation
import zlib

/// Reads CVM CSV entries directly on iOS; no subprocess or extracted files.
enum ZIPReader {
    static func read(_ url: URL, entry: String? = nil) throws -> Data {
        let bytes = [UInt8](try Data(contentsOf: url))
        func fail() -> MarketDataError { .badResponse("a CVM archive") }
        func u16(_ p: Int) throws -> Int {
            guard p >= 0, p + 2 <= bytes.count else { throw fail() }
            return Int(bytes[p]) | Int(bytes[p + 1]) << 8
        }
        func u32(_ p: Int) throws -> Int { try u16(p) | u16(p + 2) << 16 }
        guard bytes.count >= 22 else { throw fail() }
        var end = bytes.count - 22
        while end >= max(0, bytes.count - 65557), try u32(end) != 0x06054b50 { end -= 1 }
        guard end >= 0, try u32(end) == 0x06054b50 else { throw fail() }
        let count = try u16(end + 10)
        var offset = try u32(end + 16)
        var output = Data()
        for _ in 0..<count {
            guard try u32(offset) == 0x02014b50 else { throw fail() }
            let method = try u16(offset + 10), size = try u32(offset + 20), expanded = try u32(offset + 24)
            let nameLength = try u16(offset + 28), extra = try u16(offset + 30), comment = try u16(offset + 32)
            let local = try u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { throw fail() }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extra + comment
            guard !name.hasSuffix("/"), entry == nil || name == entry else { continue }
            guard try u16(local + 6) & 1 == 0, try u32(local) == 0x04034b50 else { throw fail() }
            let start = try local + 30 + u16(local + 26) + u16(local + 28)
            guard expanded <= 512_000_000, start >= 0, start + size <= bytes.count else { throw fail() }
            let outputStart = output.count
            let expectedCRC = try u32(offset - 46 - nameLength - extra - comment + 16)
            if method == 0 { output.append(contentsOf: bytes[start..<(start + size)]) }
            else if method == 8 {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw fail() }
                defer { inflateEnd(&stream) }
                var inflated = [UInt8](repeating: 0, count: max(expanded, 1))
                let status = bytes.withUnsafeBufferPointer { input in
                    inflated.withUnsafeMutableBufferPointer { buffer in
                        stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.advanced(by: start))
                        stream.avail_in = uInt(size)
                        stream.next_out = buffer.baseAddress!
                        stream.avail_out = uInt(buffer.count)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == expanded else { throw fail() }
                output.append(contentsOf: inflated.prefix(expanded))
            } else { throw fail() }
            let extracted = output.subdata(in: outputStart..<output.count)
            let actualCRC = extracted.withUnsafeBytes { raw in
                crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count))
            }
            guard actualCRC == expectedCRC, extracted.count == expanded else { throw fail() }
            if entry != nil { return output }
        }
        guard !output.isEmpty else { throw fail() }
        return output
    }
}

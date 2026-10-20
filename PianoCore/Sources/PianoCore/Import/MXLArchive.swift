import Foundation
#if canImport(Compression)
import Compression
#endif

/// Compressed MusicXML (`.mxl`): a ZIP holding the score, with `META-INF/container.xml` naming it.
/// Only what `.mxl` files use: stored or deflated entries, no encryption, no ZIP64.
enum MXLArchive {
    struct Entry {
        var method: Int
        var compressedSize: Int
        var size: Int
        var localHeader: Int
    }

    static func isZip(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    /// The MusicXML document inside the archive.
    static func scoreData(from zip: Data) throws -> Data {
        let bytes = [UInt8](zip)
        let entries = try centralDirectory(bytes)
        if let container = entries["META-INF/container.xml"],
           let root = try? XMLTree.parse(extract(container, from: bytes)),
           let path = root.child("rootfiles")?.children("rootfile").first?.attributes["full-path"],
           let entry = entries[path] {
            return try extract(entry, from: bytes)
        }
        let candidates = entries.keys.filter { !$0.hasPrefix("META-INF/") && ($0.hasSuffix(".musicxml") || $0.hasSuffix(".xml")) }.sorted()
        guard let name = candidates.first, let entry = entries[name] else { throw MusicXMLError.malformed("no score in the .mxl archive") }
        return try extract(entry, from: bytes)
    }

    static func centralDirectory(_ bytes: [UInt8]) throws -> [String: Entry] {
        // End of central directory: signature, then counts, size and offset of the directory.
        guard bytes.count >= 22,
              let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1).first(where: { u32(bytes, $0) == 0x0605_4B50 })
        else { throw MusicXMLError.malformed("not a ZIP archive") }
        let count = u16(bytes, end + 10)
        var offset = u32(bytes, end + 16)
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4B50 else { throw MusicXMLError.malformed("bad ZIP directory") }
            let nameLength = u16(bytes, offset + 28), extraLength = u16(bytes, offset + 30), commentLength = u16(bytes, offset + 32)
            guard offset + 46 + nameLength <= bytes.count else { throw MusicXMLError.malformed("bad ZIP directory") }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(method: u16(bytes, offset + 10), compressedSize: u32(bytes, offset + 20),
                                  size: u32(bytes, offset + 24), localHeader: u32(bytes, offset + 42))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func extract(_ entry: Entry, from bytes: [UInt8]) throws -> Data {
        let header = entry.localHeader
        guard header + 30 <= bytes.count, u32(bytes, header) == 0x0403_4B50 else { throw MusicXMLError.malformed("bad ZIP entry") }
        let start = header + 30 + u16(bytes, header + 26) + u16(bytes, header + 28)
        guard start + entry.compressedSize <= bytes.count else { throw MusicXMLError.malformed("truncated ZIP entry") }
        let compressed = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(compressed, size: entry.size)
        default:
            throw MusicXMLError.unsupportedFormat("ZIP compression method \(entry.method)")
        }
    }

    private static func inflate(_ compressed: [UInt8], size: Int) throws -> Data {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        // COMPRESSION_ZLIB is raw DEFLATE, which is what ZIP stores.
        let written = compressed.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, size, source.baseAddress!, compressed.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw MusicXMLError.malformed("couldn't decompress the .mxl archive") }
        return Data(output)
        #else
        throw MusicXMLError.unsupportedFormat("compressed .mxl on this platform; export uncompressed MusicXML")
        #endif
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int {
        i + 2 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> Int {
        i + 4 <= b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 : 0
    }
}

import Foundation

/// Compact on-disk cache for a `CodeTable`.
///
/// Layout (little-endian):
///
///     Header (32 bytes)
///       magic:      u32 = 'CQLB'
///       version:    u32 = 1
///       entryCount: u32
///       blobSize:   u32
///       nameOff:    u32
///       nameLen:    u32
///       reserved:   u32 x2
///
///     Entries (20 bytes each, already sorted by code asc then weight desc)
///       textOff:  u32
///       textLen:  u32
///       codeOff:  u32
///       codeLen:  u32
///       weight:   u32
///
///     Blob
///       raw UTF-8 bytes; entries point into this region.
public enum BinaryCache {
    static let magic: UInt32 = 0x43514C42  // 'CQLB'
    static let version: UInt32 = 1
    static let headerSize = 32
    static let entryRecordSize = 20

    public enum Error: Swift.Error, CustomStringConvertible {
        case badMagic
        case badVersion(UInt32)
        case truncated
        case invalidOffset

        public var description: String {
            switch self {
            case .badMagic: return "binary cache: bad magic"
            case .badVersion(let v): return "binary cache: unsupported version \(v)"
            case .truncated: return "binary cache: truncated file"
            case .invalidOffset: return "binary cache: invalid offset"
            }
        }
    }

    // MARK: - Write

    public static func write(_ table: CodeTable, to url: URL) throws {
        let entries = table.allEntries()
        var blob = Data()
        blob.reserveCapacity(entries.count * 8 + table.name.utf8.count)

        // Dedup strings so repeated words/codes share storage. Hot path in English dict.
        var interned: [String: (offset: UInt32, length: UInt32)] = [:]
        interned.reserveCapacity(entries.count)

        func intern(_ s: String) -> (UInt32, UInt32) {
            if let hit = interned[s] { return hit }
            let bytes = s.utf8
            let off = UInt32(blob.count)
            let len = UInt32(bytes.count)
            blob.append(contentsOf: bytes)
            interned[s] = (off, len)
            return (off, len)
        }

        let (nameOff, nameLen) = intern(table.name)

        // Pre-allocate entries section.
        var entriesBytes = Data(count: entries.count * entryRecordSize)
        entriesBytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt32.self)
            for (i, e) in entries.enumerated() {
                let (tOff, tLen) = intern(e.text)
                let (cOff, cLen) = intern(e.code)
                let base = i * 5
                p[base + 0] = tOff
                p[base + 1] = tLen
                p[base + 2] = cOff
                p[base + 3] = cLen
                p[base + 4] = e.weight
            }
        }

        // Header.
        var header = Data(count: headerSize)
        header.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt32.self)
            p[0] = magic
            p[1] = version
            p[2] = UInt32(entries.count)
            p[3] = UInt32(blob.count)
            p[4] = nameOff
            p[5] = nameLen
            p[6] = 0
            p[7] = 0
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Write header + entries + blob atomically.
        var file = Data()
        file.reserveCapacity(headerSize + entriesBytes.count + blob.count)
        file.append(header)
        file.append(entriesBytes)
        file.append(blob)
        try file.write(to: url, options: [.atomic])
    }

    // MARK: - Read

    public static func read(from url: URL) throws -> CodeTable {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= headerSize else { throw Error.truncated }

        let magicVal: UInt32 = data.u32(at: 0)
        guard magicVal == magic else { throw Error.badMagic }
        let versionVal: UInt32 = data.u32(at: 4)
        guard versionVal == version else { throw Error.badVersion(versionVal) }

        let entryCount = Int(data.u32(at: 8))
        let blobSize = Int(data.u32(at: 12))
        let nameOff = Int(data.u32(at: 16))
        let nameLen = Int(data.u32(at: 20))

        let entriesStart = headerSize
        let entriesEnd = entriesStart + entryCount * entryRecordSize
        let blobStart = entriesEnd
        let blobEnd = blobStart + blobSize
        guard data.count >= blobEnd else { throw Error.truncated }

        let blob = data.subdata(in: blobStart..<blobEnd)

        func readString(offset: Int, length: Int) throws -> String {
            guard offset + length <= blob.count else { throw Error.invalidOffset }
            let slice = blob.subdata(in: offset..<(offset + length))
            return String(data: slice, encoding: .utf8) ?? ""
        }

        let name = try readString(offset: nameOff, length: nameLen)

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        // Direct pointer walk for speed — avoid per-record Data subdata allocations.
        try data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: entriesStart)
            for i in 0..<entryCount {
                let p = base.advanced(by: i * entryRecordSize).assumingMemoryBound(to: UInt32.self)
                let tOff = Int(p[0])
                let tLen = Int(p[1])
                let cOff = Int(p[2])
                let cLen = Int(p[3])
                let w = p[4]

                guard tOff + tLen <= blob.count, cOff + cLen <= blob.count else {
                    throw Error.invalidOffset
                }

                let text = blob.withUnsafeBytes { bb -> String in
                    let ptr = bb.baseAddress!.advanced(by: tOff).assumingMemoryBound(to: UInt8.self)
                    return String(
                        decoding: UnsafeBufferPointer(start: ptr, count: tLen),
                        as: UTF8.self
                    )
                }
                let code = blob.withUnsafeBytes { bb -> String in
                    let ptr = bb.baseAddress!.advanced(by: cOff).assumingMemoryBound(to: UInt8.self)
                    return String(
                        decoding: UnsafeBufferPointer(start: ptr, count: cLen),
                        as: UTF8.self
                    )
                }
                entries.append(Entry(text: text, code: code, weight: w))
            }
        }

        // Entries are already sorted on write, skip resort in constructor.
        return CodeTable(name: name, presortedEntries: entries)
    }
}

private extension Data {
    func u32(at offset: Int) -> UInt32 {
        return withUnsafeBytes { raw in
            raw.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
}

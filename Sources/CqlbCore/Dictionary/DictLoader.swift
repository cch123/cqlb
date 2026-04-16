import Foundation

public enum DictLoadError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case invalidFormat(String)
    case readFailed(underlying: Error)

    public var description: String {
        switch self {
        case .fileNotFound(let url): return "Dictionary file not found: \(url.path)"
        case .invalidFormat(let msg): return "Invalid dictionary format: \(msg)"
        case .readFailed(let err): return "Read failed: \(err)"
        }
    }
}

public struct DictLoadOptions: Sendable {
    public var maxEntries: Int?          // hard cap
    public var minWeight: UInt32         // drop entries below this weight
    public var skipStemColumn: Bool      // fourth column exists but we don't need it

    public static let `default` = DictLoadOptions(maxEntries: nil, minWeight: 0, skipStemColumn: true)

    public init(maxEntries: Int? = nil, minWeight: UInt32 = 0, skipStemColumn: Bool = true) {
        self.maxEntries = maxEntries
        self.minWeight = minWeight
        self.skipStemColumn = skipStemColumn
    }
}

/// Parser for Rime `.dict.yaml` files.
///
/// Format: YAML header (`name`, `columns`, `sort`, ...) terminated by `...` on its own line,
/// followed by tab-separated data rows. Data row format depends on declared columns.
public enum DictLoader {

    /// Load a dictionary, preferring a binary cache if one exists and is fresh.
    /// On cache miss, parses the YAML source and writes a new cache.
    public static func loadCached(
        source: URL,
        cache: URL,
        options: DictLoadOptions = .default
    ) throws -> (table: CodeTable, fromCache: Bool) {
        let fm = FileManager.default
        if fm.fileExists(atPath: cache.path),
           let srcAttrs = try? fm.attributesOfItem(atPath: source.path),
           let cacheAttrs = try? fm.attributesOfItem(atPath: cache.path),
           let srcMtime = srcAttrs[.modificationDate] as? Date,
           let cacheMtime = cacheAttrs[.modificationDate] as? Date,
           cacheMtime >= srcMtime
        {
            do {
                let table = try BinaryCache.read(from: cache)
                return (table, true)
            } catch {
                // fall through: rebuild cache
            }
        }

        let table = try load(from: source, options: options)
        try? BinaryCache.write(table, to: cache)
        return (table, false)
    }

    public static func load(
        from url: URL,
        options: DictLoadOptions = .default
    ) throws -> CodeTable {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DictLoadError.fileNotFound(url)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw DictLoadError.readFailed(underlying: error)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw DictLoadError.invalidFormat("file is not valid UTF-8")
        }

        return try parse(text: text, sourceName: url.lastPathComponent, options: options)
    }

    public static func parse(
        text: String,
        sourceName: String,
        options: DictLoadOptions = .default
    ) throws -> CodeTable {
        var name = sourceName
        var columns: [String] = ["text", "code", "weight"]  // sensible default
        var inHeader = true
        var dataStart: String.Index? = nil

        // Scan header, capture `name:` and `columns:` (simplified YAML reader — we only
        // accept the subset Rime dict files use).
        var idx = text.startIndex
        while idx < text.endIndex {
            let lineEnd = text[idx...].firstIndex(of: "\n") ?? text.endIndex
            let rawLine = text[idx..<lineEnd]
            let line = rawLine.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")

            if inHeader {
                if line == "..." {
                    inHeader = false
                    dataStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                    break
                } else if line.hasPrefix("name:") {
                    let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    name = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else if line.hasPrefix("columns:") {
                    // look-ahead collect following `- foo` lines
                    var p = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                    var collected: [String] = []
                    while p < text.endIndex {
                        let nextLineEnd = text[p...].firstIndex(of: "\n") ?? text.endIndex
                        let nl = text[p..<nextLineEnd].trimmingCharacters(in: .whitespaces)
                        if nl.hasPrefix("- ") {
                            collected.append(String(nl.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
                            p = nextLineEnd < text.endIndex ? text.index(after: nextLineEnd) : text.endIndex
                        } else {
                            break
                        }
                    }
                    if !collected.isEmpty { columns = collected }
                }
            }
            idx = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }

        guard let start = dataStart else {
            throw DictLoadError.invalidFormat("missing `...` header terminator")
        }

        // Locate column indices.
        guard let textCol = columns.firstIndex(of: "text"),
              let codeCol = columns.firstIndex(of: "code") else {
            throw DictLoadError.invalidFormat("columns must include `text` and `code`")
        }
        let weightCol = columns.firstIndex(of: "weight")

        // Parse rows.
        var entries: [Entry] = []
        entries.reserveCapacity(1 << 17)

        var cursor = start
        let cap = options.maxEntries ?? Int.max

        while cursor < text.endIndex && entries.count < cap {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            defer { cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex }

            let line = text[cursor..<lineEnd]
            if line.isEmpty { continue }
            if line.first == "#" { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.first == "#" { continue }

            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            if cols.count <= max(textCol, codeCol) { continue }

            let textVal = String(cols[textCol])
            let codeVal = String(cols[codeCol])
            if textVal.isEmpty || codeVal.isEmpty { continue }

            var weight: UInt32 = 0
            if let wc = weightCol, wc < cols.count {
                weight = UInt32(cols[wc]) ?? 0
            }
            if weight < options.minWeight { continue }

            entries.append(Entry(text: textVal, code: codeVal, weight: weight))
        }

        // If we were asked to cap by count, take the highest-weight entries first.
        if let cap = options.maxEntries, entries.count > cap {
            entries.sort { $0.weight > $1.weight }
            entries.removeLast(entries.count - cap)
        }

        return CodeTable(name: name, entries: entries)
    }
}

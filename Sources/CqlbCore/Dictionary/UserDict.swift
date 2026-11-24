import Foundation

/// User dictionary (用户词库): words the user adds on top of the main table.
///
/// File format is the data section of Rime's `cqlb.src.dict.yaml`, one entry
/// per line, tab-separated:
///
///     词组<TAB>编码            explicit code, ranked after main-table rivals
///     词组<TAB>编码<TAB>2      weight 2 > main-table weight 1 ⇒ ranked first
///     词组                    no code: auto-encoded from the characters' stems
///
/// Lines starting with `#` are comments. An optional YAML header terminated
/// by `...` is skipped, so a Rime `*.dict.yaml` user dictionary can be used
/// unmodified.
public enum UserDict {

    /// Per-scheme user dictionary, since codes are scheme-specific:
    /// `~/Library/Application Support/cqlb/user.dict.yaml` for 两笔 (the
    /// original name, kept for existing users) and `user.cqyx.dict.yaml`
    /// for 音形.
    public static func url(for scheme: Scheme) -> URL {
        let name = scheme == .cqlb ? "user.dict.yaml" : "user.\(scheme.rawValue).dict.yaml"
        return ConfigStore.url.deletingLastPathComponent().appendingPathComponent(name)
    }

    public static let template = """
    # 用户词库
    #
    # 每行一个词条，字段之间用 Tab 分隔（不能用空格）：
    #
    #   词组<Tab>编码          与原词库重码时排在后面
    #   词组<Tab>编码<Tab>2    与原词库重码时排在前面
    #   词组                  不写编码：按构词规则自动编码
    #
    # 以 # 开头的行是注释。保存后自动生效，无需重启输入法。
    #
    # 示例（去掉行首 # 生效）：
    #例壹\tdhsl
    #例贰\tdhsl\t2
    #春眠不觉晓处处闻啼鸟

    """

    /// Create the scheme's user dictionary with an explanatory template if
    /// absent.
    public static func createTemplateIfMissing(for scheme: Scheme) {
        let fm = FileManager.default
        let url = url(for: scheme)
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(template.utf8).write(to: url, options: [.atomic])
    }

    public struct ParseResult: Sendable {
        public var entries: [Entry] = []
        /// Lines that could not be turned into an entry (no code and not
        /// auto-encodable), for diagnostics.
        public var skipped: [String] = []
    }

    /// Parse user-dictionary text. `stem` returns the full (构词) code of a
    /// single character and is only consulted for entries without a code.
    public static func parse(text: String, stem: (Character) -> String?) -> ParseResult {
        var result = ParseResult()
        var body = Substring(text)
        // Skip a Rime YAML header if present.
        if body.hasPrefix("---") || body.hasPrefix("\u{FEFF}---") || body.hasPrefix("#") {
            for marker in ["\n...\n", "\n...\r\n"] {
                if let r = body.range(of: marker) {
                    body = body[r.upperBound...]
                    break
                }
            }
        }

        var seen = Set<Entry>()
        for rawLine in body.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            if rawLine.first == "#" { continue }
            let cols = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
            let word = cols[0].trimmingCharacters(in: .whitespaces)
            if word.isEmpty || word.first == "#" { continue }

            var code = cols.count > 1 ? cols[1].trimmingCharacters(in: .whitespaces) : ""
            if code.isEmpty {
                guard let auto = WordEncoder.encode(word, stem: stem) else {
                    result.skipped.append(word)
                    continue
                }
                code = auto
            }
            let weight = cols.count > 2
                ? UInt32(cols[2].trimmingCharacters(in: .whitespaces)) ?? 0
                : 0
            let entry = Entry(text: word, code: code.lowercased(), weight: weight)
            if seen.insert(entry).inserted {
                result.entries.append(entry)
            }
        }
        return result
    }

    /// Load and parse `url`. Returns an empty result if the file is absent.
    public static func load(from url: URL, stem: (Character) -> String?) -> ParseResult {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return ParseResult() }
        return parse(text: text, stem: stem)
    }
}

/// Phrase encoder implementing the `encoder.rules` of the cqlb Rime schema:
///
///     length 2      AaAbBaBb    first two keys of each character
///     length 3      AaAbBaCa    two keys of the 1st, first key of 2nd and 3rd
///     length ≥ 4    AaBaCaZa    first key of the 1st, 2nd, 3rd and last
///
/// (Uppercase = which character, lowercase = which key of its stem.)
/// Characters without a stem — punctuation inside a phrase, for example — do
/// not take part in the encoding.
public enum WordEncoder {
    public static func encode(_ word: String, stem: (Character) -> String?) -> String? {
        let stems = word.compactMap(stem).map { Array($0) }
        func key(_ char: Int, _ index: Int) -> Character? {
            guard char < stems.count, index < stems[char].count else { return nil }
            return stems[char][index]
        }
        let picks: [Character?]
        switch stems.count {
        case 0, 1:
            return nil
        case 2:
            picks = [key(0, 0), key(0, 1), key(1, 0), key(1, 1)]
        case 3:
            picks = [key(0, 0), key(0, 1), key(1, 0), key(2, 0)]
        default:
            picks = [key(0, 0), key(1, 0), key(2, 0), key(stems.count - 1, 0)]
        }
        guard !picks.contains(where: { $0 == nil }) else { return nil }
        return String(picks.compactMap { $0 })
    }
}

/// Per-character stems (构词码) of the main table: the 4th `stem` column of
/// `cqlb.dict.yaml`, which the regular loader does not keep.
public enum StemTable {

    /// Load stems, using a binary cache keyed by the same source fingerprint
    /// scheme as the code tables.
    public static func loadCached(source: URL, cache: URL) -> [Character: String] {
        let options = DictLoadOptions(maxEntries: nil, minWeight: 0, skipStemColumn: false)
        if let fp = try? DictLoader.fingerprint(source: source, options: options) {
            if BinaryCache.readFingerprint(from: cache) == fp,
               let table = try? BinaryCache.read(from: cache)
            {
                return dictionary(from: table.allEntries())
            }
            let stems = (try? String(contentsOf: source, encoding: .utf8)).map(parse) ?? [:]
            let entries = stems.map { Entry(text: String($0.key), code: $0.value, weight: 0) }
            try? BinaryCache.write(CodeTable(name: "stems", entries: entries), to: cache, fingerprint: fp)
            return stems
        }
        return [:]
    }

    /// Extract `character → stem` from dict YAML text.
    ///
    /// Preference order per character: an explicit stem column; otherwise the
    /// longest code not excluded by the schema's `exclude_patterns`
    /// (`^[iuv].*$|[ao]$`).
    public static func parse(_ text: String) -> [Character: String] {
        var explicit: [Character: String] = [:]
        var fallback: [Character: String] = [:]
        var inData = false
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            if !inData {
                if line == "..." { inData = true }
                continue
            }
            if line.first == "#" { continue }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 2, cols[0].count == 1, let ch = cols[0].first else { continue }
            if cols.count >= 4, !cols[3].isEmpty {
                if explicit[ch] == nil { explicit[ch] = String(cols[3]) }
                continue
            }
            let code = cols[1]
            guard let first = code.first, let last = code.last,
                  !"iuv".contains(first), !"ao".contains(last)
            else { continue }
            if code.count > (fallback[ch]?.count ?? 0) { fallback[ch] = String(code) }
        }
        return fallback.merging(explicit) { _, stem in stem }
    }

    private static func dictionary(from entries: [Entry]) -> [Character: String] {
        var out: [Character: String] = [:]
        out.reserveCapacity(entries.count)
        for e in entries {
            if let ch = e.text.first { out[ch] = e.code }
        }
        return out
    }
}

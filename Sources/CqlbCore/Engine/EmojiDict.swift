import Foundation

/// In-memory map from Chinese word → list of associated emoji characters.
///
/// Source: OpenCC-format `emoji_word.txt` / `emoji_category.txt`.
/// Line format is `key<TAB>key SP emoji1 SP emoji2 …`. The value repeats the
/// key as its first space-separated token; we strip it and keep only the
/// trailing emoji tokens.
public final class EmojiDict: @unchecked Sendable {

    public static let empty = EmojiDict(mapping: [:])

    private let mapping: [String: [String]]

    public init(mapping: [String: [String]]) {
        self.mapping = mapping
    }

    public var count: Int { mapping.count }

    public func emojis(for word: String) -> [String] {
        mapping[word] ?? []
    }

    public static func load(from urls: [URL]) throws -> EmojiDict {
        var map: [String: [String]] = [:]
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if line.hasPrefix("#") { continue }
                let halves = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard halves.count == 2 else { continue }
                let key = String(halves[0]).trimmingCharacters(in: .whitespaces)
                if key.isEmpty { continue }
                let valueTokens = halves[1].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                if valueTokens.isEmpty { continue }
                // First token is typically the key itself; drop it if so.
                var emojis = valueTokens
                if emojis.first == key {
                    emojis.removeFirst()
                }
                if emojis.isEmpty { continue }
                if var existing = map[key] {
                    for e in emojis where !existing.contains(e) {
                        existing.append(e)
                    }
                    map[key] = existing
                } else {
                    map[key] = emojis
                }
            }
        }
        return EmojiDict(mapping: map)
    }
}

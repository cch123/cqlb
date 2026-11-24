import Foundation

/// Encoding scheme: which code table is loaded and the keying rules that
/// differ between tables. Both are 付东升's schemes and share the `i`-prefix
/// pinyin reverse lookup, 4-key maximum and 4-key auto-commit.
///
///                      超强两笔 (cqlb)          超强音形 (cqyx)
///     code alphabet    a–z and  ; , . /        a–z only
///     temp English     '                       ;
///     u?/v? 2-key      no special rule         auto-commit when unique
public enum Scheme: String, Codable, Sendable, CaseIterable {
    case cqlb
    case cqyx

    public var displayName: String {
        switch self {
        case .cqlb: return "超强两笔"
        case .cqyx: return "超强音形"
        }
    }

    /// Main code table file name.
    public var dictFile: String { "\(rawValue).dict.yaml" }

    /// The scheme's stock user dictionary shipped with the Rime package.
    public var stockUserDictFile: String { "\(rawValue).src.dict.yaml" }

    /// Punctuation keys that are part of the code alphabet. While composing
    /// they extend the code instead of producing punctuation.
    public var codePunctuation: Set<Character> {
        switch self {
        case .cqlb: return [";", ",", ".", "/"]
        case .cqyx: return []
        }
    }

    /// Key that starts temporary English input.
    public var englishPrefix: Character {
        switch self {
        case .cqlb: return "'"
        case .cqyx: return ";"
        }
    }

    /// 音形's `auto_select_pattern: (^[uv].$)|^.{4}$` — a two-key code
    /// starting with `u` or `v` commits by itself when it is unambiguous.
    public var autoSelectsShortUV: Bool { self == .cqyx }
}

import Foundation

/// User-editable configuration shared by the IME and its settings UI via a
/// JSON file at `~/Library/Application Support/cqlb/config.json`.
public struct Config: Codable, Sendable, Equatable {
    public var version: Int = 1
    /// Encoding scheme (code table). Switching takes effect immediately.
    public var scheme: Scheme = .cqlb
    public var appearance: Appearance = .init()
    public var functions: Functions = .init()
    public var shortcuts: Shortcuts = .init()

    public struct Appearance: Codable, Sendable, Equatable {
        public var font: String = "PingFang SC"
        public var fontSize: Double = 16
        public var candidateCount: Int = 6
        public var layout: Layout = .horizontal
        public var colorScheme: ColorScheme = .system
        public var accentColor: AccentColor = .red
        /// Show the code row at the top of the candidate window in main
        /// mode. Off by default: the code is already shown inline in the
        /// text field, and candidates carry next-key hints.
        public var showPreedit: Bool = false
        /// Light effects on the candidate window: flowing border light,
        /// glow under the highlight, accent-tinted glass.
        public var glow: Bool = true

        public enum Layout: String, Codable, Sendable, CaseIterable { case horizontal, vertical }
        public enum ColorScheme: String, Codable, Sendable, CaseIterable { case system, light, dark }
        public enum AccentColor: String, Codable, Sendable, CaseIterable {
            case red, orange, green, blue, purple, teal
        }
    }

    public struct Functions: Codable, Sendable, Equatable {
        public var emojiSuggestion: Bool = true
        /// Both code tables contain Hanzi outside GB2312, so filtering is opt-in.
        public var gb2312Filter: Bool = false
        public var tempEnglish: Bool = true
        public var tempPinyin: Bool = true
        public var reverseLookupDisplay: ReverseLookup = .code

        public enum ReverseLookup: String, Codable, Sendable, CaseIterable {
            case none, code, pinyin, both
        }
    }

    public struct Shortcuts: Codable, Sendable, Equatable {
        public var toggleChineseEnglish: ToggleKey = .optionSpace
        public var shiftTap: ShiftTap = .both
        /// Retained for config-file compatibility. Esc is the only clear key;
        /// it is a platform-wide cancel convention, so it is not remappable.
        public var clearBuffer: String = "escape"

        /// Chord that toggles Chinese/English mode.
        /// Control+Space and Command+Space are deliberately absent: macOS
        /// binds them to input-source switching and Spotlight.
        public enum ToggleKey: String, Codable, Sendable, CaseIterable {
            case optionSpace = "option_space"
            case shiftSpace = "shift_space"
            case none
        }

        /// Which Shift key toggles Chinese/English on a quick tap.
        public enum ShiftTap: String, Codable, Sendable, CaseIterable {
            case both, left, right, none
        }
    }

    public init() {}
}

// MARK: - Tolerant decoding
//
// Synthesized `Decodable` ignores property default values: a missing key
// throws `keyNotFound`, and `ConfigStore.load()` would then silently fall back
// to `Config()` — i.e. adding any field in a new release would reset every
// existing user's settings. Each field is decoded independently instead, so a
// missing, mistyped or unknown-enum value only resets that one field.

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

extension Config {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        version = c.value(.version, default: d.version)
        scheme = c.value(.scheme, default: d.scheme)
        appearance = c.value(.appearance, default: d.appearance)
        functions = c.value(.functions, default: d.functions)
        shortcuts = c.value(.shortcuts, default: d.shortcuts)
    }
}

extension Config.Appearance {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.Appearance()
        font = c.value(.font, default: d.font)
        fontSize = c.value(.fontSize, default: d.fontSize)
        candidateCount = c.value(.candidateCount, default: d.candidateCount)
        layout = c.value(.layout, default: d.layout)
        colorScheme = c.value(.colorScheme, default: d.colorScheme)
        accentColor = c.value(.accentColor, default: d.accentColor)
        showPreedit = c.value(.showPreedit, default: d.showPreedit)
        glow = c.value(.glow, default: d.glow)
    }
}

extension Config.Functions {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.Functions()
        emojiSuggestion = c.value(.emojiSuggestion, default: d.emojiSuggestion)
        gb2312Filter = c.value(.gb2312Filter, default: d.gb2312Filter)
        tempEnglish = c.value(.tempEnglish, default: d.tempEnglish)
        tempPinyin = c.value(.tempPinyin, default: d.tempPinyin)
        reverseLookupDisplay = c.value(.reverseLookupDisplay, default: d.reverseLookupDisplay)
    }
}

extension Config.Shortcuts {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.Shortcuts()
        toggleChineseEnglish = c.value(.toggleChineseEnglish, default: d.toggleChineseEnglish)
        shiftTap = c.value(.shiftTap, default: d.shiftTap)
        clearBuffer = c.value(.clearBuffer, default: d.clearBuffer)
    }
}

public enum ConfigStore {
    public static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("cqlb/config.json")
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        return decode(data)
    }

    /// Decode config JSON. Never throws: malformed input yields defaults for
    /// the affected fields (or the whole config if the JSON is unparseable).
    public static func decode(_ data: Data) -> Config {
        (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
    }

    public static func save(_ config: Config) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }
}

public extension EngineConfig {
    /// Map the user-facing `Config` struct into an `EngineConfig` the core
    /// engine understands.
    static func from(_ config: Config) -> EngineConfig {
        EngineConfig(
            // Clamp: a page size of 0 would make paging loop forever, and
            // more than 9 slots cannot be addressed by digit keys.
            candidateCount: min(max(config.appearance.candidateCount, 1), 9),
            maxCodeLength: 4,
            autoSelect: true,
            enableTempEnglish: config.functions.tempEnglish,
            enableTempPinyin: config.functions.tempPinyin,
            enableEmoji: config.functions.emojiSuggestion,
            enableGb2312: config.functions.gb2312Filter,
            enableRecognizer: true,
            annotation: EngineConfig.Annotation(config.functions.reverseLookupDisplay),
            scheme: config.scheme
        )
    }
}

extension EngineConfig.Annotation {
    init(_ mode: Config.Functions.ReverseLookup) {
        switch mode {
        case .none:   self = .none
        case .code:   self = .code
        case .pinyin: self = .pinyin
        case .both:   self = .both
        }
    }
}

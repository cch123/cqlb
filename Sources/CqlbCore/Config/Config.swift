import Foundation

/// User-editable configuration, shared by the IME and the Settings app via a
/// JSON file at `~/Library/Application Support/cqlb/config.json`.
public struct Config: Codable, Sendable, Equatable {
    public var version: Int = 1
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

        public enum Layout: String, Codable, Sendable, CaseIterable { case horizontal, vertical }
        public enum ColorScheme: String, Codable, Sendable, CaseIterable { case system, light, dark }
        public enum AccentColor: String, Codable, Sendable, CaseIterable {
            case red, orange, green, blue, purple, teal
        }
    }

    public struct Functions: Codable, Sendable, Equatable {
        public var emojiSuggestion: Bool = true
        public var gb2312Filter: Bool = true
        public var tempEnglish: Bool = true
        public var tempPinyin: Bool = true
        public var reverseLookupDisplay: ReverseLookup = .code

        public enum ReverseLookup: String, Codable, Sendable, CaseIterable {
            case none, code, pinyin, both
        }
    }

    public struct Shortcuts: Codable, Sendable, Equatable {
        public var toggleChineseEnglish: String = "option_space"
        public var clearBuffer: String = "escape"
    }

    public init() {}
}

public enum ConfigStore {
    public static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("cqlb/config.json")
    }

    public static func load() -> Config {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else {
            return Config()
        }
        return cfg
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
            candidateCount: config.appearance.candidateCount,
            maxCodeLength: 4,
            autoSelect: true,
            enableTempEnglish: config.functions.tempEnglish,
            enableTempPinyin: config.functions.tempPinyin,
            enableEmoji: config.functions.emojiSuggestion,
            enableGb2312: config.functions.gb2312Filter,
            enableRecognizer: true
        )
    }
}

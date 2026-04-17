import Foundation
import CqlbCore

/// Process-wide holder for dictionaries and the engine. Loads once, watches
/// the config file for live updates from CqlbSettings.
///
/// Unlike the CqlbApp (CGEventTap) variant, this IME host:
/// - does NOT manage a login item (IME bundles are loaded on-demand by
///   `TextInputMenuAgent`)
/// - is still a single shared Engine — per-client state isolation in this
///   codebase was an explicit decision (see plan; user opted for shared).
///   `CqlbInputController` calls `engine.reset()` on activate/deactivate to
///   keep composition state from leaking across apps.
final class EngineHost {
    static let shared = EngineHost()

    let engine: Engine
    private(set) var config: Config
    var currentConfig: Config { config }
    private var fileWatch: DispatchSourceFileSystemObject?

    private init() {
        let cfg = ConfigStore.load()
        self.config = cfg

        Log.engine.log("loading dictionaries…")
        let start = Date()
        let resources = Self.loadResources()
        self.engine = Engine(
            resources: resources,
            config: EngineConfig.from(cfg)
        )
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        Log.engine.log("engine ready in \(ms) ms")

        if !FileManager.default.fileExists(atPath: ConfigStore.url.path) {
            try? ConfigStore.save(config)
        }
        startWatchingConfig()
    }

    private static func loadResources() -> EngineResources {
        let bundleDicts = Bundle.main.resourceURL?.appendingPathComponent("Dicts")
        let cacheDir = URL(fileURLWithPath: (
            "~/Library/Caches/cqlb" as NSString
        ).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        func loadTable(_ filename: String, cap: Int? = nil) -> CodeTable? {
            let candidates: [URL?] = [
                bundleDicts?.appendingPathComponent(filename),
                URL(fileURLWithPath: (
                    "~/Library/Rime/\(filename)" as NSString
                ).expandingTildeInPath),
            ]
            for src in candidates.compactMap({ $0 }) {
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let cache = cacheDir.appendingPathComponent(filename + ".bin")
                do {
                    let result = try DictLoader.loadCached(
                        source: src,
                        cache: cache,
                        options: DictLoadOptions(
                            maxEntries: cap, minWeight: 0, skipStemColumn: true
                        )
                    )
                    let origin = result.fromCache ? "cache" : "yaml"
                    Log.engine.log("loaded \(filename) [\(origin)] count=\(result.table.count)")
                    return result.table
                } catch {
                    Log.engine.error("failed to load \(filename): \(error)")
                }
            }
            return nil
        }

        let main = loadTable("cqlb.dict.yaml") ?? CodeTable(name: "empty", entries: [])
        let pinyin = loadTable("ipinyin.dict.yaml")
        let english = loadTable("english.dict.yaml")

        var emojiURLs: [URL] = []
        if let bundled = bundleDicts?.appendingPathComponent("emoji_word.txt") {
            emojiURLs.append(bundled)
        }
        if let bundled = bundleDicts?.appendingPathComponent("emoji_category.txt") {
            emojiURLs.append(bundled)
        }
        emojiURLs.append(URL(fileURLWithPath: (
            "~/Library/Rime/opencc/emoji_word.txt" as NSString
        ).expandingTildeInPath))
        emojiURLs.append(URL(fileURLWithPath: (
            "~/Library/Rime/opencc/emoji_category.txt" as NSString
        ).expandingTildeInPath))
        let emoji = (try? EmojiDict.load(from: emojiURLs)) ?? EmojiDict.empty

        return EngineResources(main: main, pinyin: pinyin, english: english, emoji: emoji)
    }

    private func startWatchingConfig() {
        let path = ConfigStore.url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.reloadConfig()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.fileWatch = src
    }

    private func reloadConfig() {
        let cfg = ConfigStore.load()
        self.config = cfg
        self.engine.config = EngineConfig.from(cfg)
        Log.general.log("config reloaded")
    }

    /// Called on activation to pick up config changes that the file watcher
    /// may have missed (Settings uses atomic writes which invalidate the
    /// watched fd).
    func forceReloadConfig() {
        reloadConfig()
    }
}

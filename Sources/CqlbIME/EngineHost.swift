import Foundation
import CqlbCore

/// Process-wide holder for dictionaries and the engine. Loads once, watches
/// the config file for live updates from the in-process settings UI.
///
/// IME bundles are loaded on demand by `TextInputMenuAgent`, so this host
/// intentionally does not manage a login item. The engine is shared within
/// the process; `CqlbInputController` resets it on activate/deactivate so
/// composition state does not leak across apps.
final class EngineHost {
    static let shared = EngineHost()

    let engine: Engine
    private(set) var config: Config
    var currentConfig: Config { config }
    private var fileWatch: DispatchSourceFileSystemObject?

    /// Main table of the active scheme as shipped, without user-dictionary
    /// entries; the engine's table is rebuilt from this whenever the user
    /// dictionary changes.
    private var baseMain: CodeTable
    /// Scheme whose table is currently loaded.
    private var loadedScheme: Scheme
    private var userDictStamp: FileStamp?
    /// Per-character stems of the active scheme, for auto-encoding code-less
    /// user entries. Loaded on first need; dropped on scheme switch.
    private var stemsCache: [Character: String]?
    private var stems: [Character: String] {
        if let cached = stemsCache { return cached }
        let loaded = Self.loadStems(loadedScheme)
        stemsCache = loaded
        return loaded
    }

    private init() {
        let cfg = ConfigStore.load()
        self.config = cfg

        Log.engine.log("loading dictionaries…")
        let start = Date()
        let resources = Self.loadResources(scheme: cfg.scheme)
        self.baseMain = resources.main
        self.loadedScheme = cfg.scheme
        self.engine = Engine(
            resources: resources,
            config: EngineConfig.from(cfg)
        )
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        Log.engine.log("engine ready in \(ms) ms")

        if !FileManager.default.fileExists(atPath: ConfigStore.url.path) {
            try? ConfigStore.save(config)
        }
        loadedStamp = Self.stamp()
        UserDict.createTemplateIfMissing(for: cfg.scheme)
        reloadUserDictIfChanged(force: true)
        startWatchingConfig()
    }

    private static let bundleDicts = Bundle.main.resourceURL?.appendingPathComponent("Dicts")
    private static let cacheDir = URL(fileURLWithPath: (
        "~/Library/Caches/cqlb" as NSString
    ).expandingTildeInPath)

    /// First existing location of a dictionary file: app bundle, then
    /// `~/Library/Rime`.
    private static func sourceURLs(_ filename: String) -> [URL] {
        let candidates: [URL?] = [
            bundleDicts?.appendingPathComponent(filename),
            URL(fileURLWithPath: ("~/Library/Rime/\(filename)" as NSString).expandingTildeInPath),
        ]
        return candidates.compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func loadStems(_ scheme: Scheme) -> [Character: String] {
        guard let src = sourceURLs(scheme.dictFile).first else { return [:] }
        let cache = cacheDir.appendingPathComponent(DictLoader.cacheFileName(for: src) + ".stems")
        let stems = StemTable.loadCached(source: src, cache: cache)
        Log.engine.log("loaded stems count=\(stems.count)")
        return stems
    }

    // MARK: - User dictionary

    /// Sources merged into the main table: the scheme's stock user
    /// dictionary (`<scheme>.src.dict.yaml`) and the user's own file.
    private static func userDictURLs(_ scheme: Scheme) -> [URL] {
        sourceURLs(scheme.stockUserDictFile).prefix(1) + [UserDict.url(for: scheme)]
    }

    /// Load the main table of `scheme` and make it the engine's table.
    /// Called when the scheme setting changes.
    private func switchScheme(to scheme: Scheme) {
        let start = Date()
        baseMain = Self.loadTable(scheme.dictFile) ?? CodeTable(name: "empty", entries: [])
        loadedScheme = scheme
        stemsCache = nil
        UserDict.createTemplateIfMissing(for: scheme)
        reloadUserDictIfChanged(force: true)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        Log.engine.log("switched scheme to \(scheme.rawValue) in \(ms) ms")
    }

    /// Rebuild the engine's main table if the user dictionary file changed.
    func reloadUserDictIfChanged(force: Bool = false) {
        let current = Self.stamp(of: UserDict.url(for: loadedScheme))
        guard force || current != userDictStamp else { return }
        userDictStamp = current

        var entries: [Entry] = []
        var skipped: [String] = []
        for url in Self.userDictURLs(loadedScheme) {
            let parsed = UserDict.load(from: url) { [unowned self] ch in self.stems[ch] }
            entries += parsed.entries
            skipped += parsed.skipped
        }
        engine.replaceMain(baseMain.merging(entries))
        Log.engine.log("user dictionary: \(entries.count) entries, \(skipped.count) skipped")
        if !skipped.isEmpty {
            // Entry text only; never log what the user types.
            Log.engine.error("user dictionary: cannot auto-encode \(skipped.count) entries (need ≥2 encodable characters)")
        }
    }

    private static func loadTable(_ filename: String, cap: Int? = nil) -> CodeTable? {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Remove the pre-fingerprint cache (`<name>.bin`), now orphaned.
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(filename + ".bin"))
        for src in sourceURLs(filename) {
            let cache = cacheDir.appendingPathComponent(DictLoader.cacheFileName(for: src))
            do {
                let result = try DictLoader.loadCached(
                    source: src,
                    cache: cache,
                    options: DictLoadOptions(maxEntries: cap, minWeight: 0, skipStemColumn: true)
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

    private static func loadResources(scheme: Scheme) -> EngineResources {
        let main = loadTable(scheme.dictFile) ?? CodeTable(name: "empty", entries: [])
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

    /// Watch the config *directory*, not the file. `ConfigStore.save` writes
    /// atomically (temp file + rename), which replaces the inode: a watcher
    /// on the file's fd sees one `.rename` and then never fires again. A
    /// directory fd stays valid and reports `.write` on every entry change.
    private func startWatchingConfig() {
        let dir = ConfigStore.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.general.error("config watch: cannot open \(dir.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.reloadConfigIfChanged()
            self?.reloadUserDictIfChanged()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.fileWatch = src
    }

    /// (mtime, size) of the config file at the last load; nil if absent.
    private var loadedStamp: FileStamp?

    private struct FileStamp: Equatable {
        let mtime: Date
        let size: UInt64
    }

    private static func stamp(of url: URL = ConfigStore.url) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date
        else { return nil }
        return FileStamp(mtime: mtime, size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0)
    }

    private func applyConfig(_ cfg: Config) {
        self.config = cfg
        self.engine.config = EngineConfig.from(cfg)
        if cfg.scheme != loadedScheme {
            switchScheme(to: cfg.scheme)
        }
    }

    /// Reload only if the file changed since the last load. Cheap (one
    /// `stat`), so it is safe to call on every client activation.
    func reloadConfigIfChanged() {
        let current = Self.stamp()
        guard current != loadedStamp else { return }
        loadedStamp = current
        let cfg = ConfigStore.load()
        guard cfg != config else { return }
        applyConfig(cfg)
        Log.general.log("config reloaded")
    }

    /// Unconditional reload, used right after the in-process Settings UI saves.
    func forceReloadConfig() {
        loadedStamp = Self.stamp()
        applyConfig(ConfigStore.load())
        Log.general.log("config reloaded")
    }
}

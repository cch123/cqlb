import XCTest
@testable import CqlbCore

// MARK: - Fixtures

private func makeEngine(
    main: [Entry] = defaultMain,
    pinyin: [Entry]? = defaultPinyin,
    english: [Entry]? = defaultEnglish,
    configure: (inout EngineConfig) -> Void = { _ in }
) -> Engine {
    var cfg = EngineConfig.default
    configure(&cfg)
    return Engine(
        resources: EngineResources(
            main: CodeTable(name: "main", entries: main),
            pinyin: pinyin.map { CodeTable(name: "py", entries: $0) },
            english: english.map { CodeTable(name: "en", entries: $0) },
            emoji: .empty
        ),
        config: cfg
    )
}

private let defaultMain: [Entry] = [
    Entry(text: "工", code: "a", weight: 10),
    Entry(text: "式", code: "ab", weight: 5),
    Entry(text: "戒", code: "abcd", weight: 5),       // unique 4-key code → auto-select
    Entry(text: "甲", code: "abce", weight: 5),       // rivals sharing abce
    Entry(text: "乙", code: "abce", weight: 3),
    Entry(text: "中", code: "ka", weight: 9),
    Entry(text: "中国", code: "kakf", weight: 9),
    Entry(text: "䶮", code: "ky", weight: 99),        // outside GB2312
    Entry(text: "①", code: "kz", weight: 1),          // symbol, must survive the filter
]

private let defaultPinyin: [Entry] = [
    Entry(text: "中", code: "izhong", weight: 0),
    Entry(text: "种", code: "izhong", weight: 0),
]

private let defaultEnglish: [Entry] = [
    Entry(text: "hello", code: "hello", weight: 0),
    Entry(text: "help", code: "help", weight: 0),
    Entry(text: "world", code: "world", weight: 0),
]

private extension Engine {
    @discardableResult
    func type(_ s: String) -> [EngineResult] {
        s.map { processKey(KeyEvent(char: $0)) }
    }
    func press(_ special: KeyEvent.Special) -> EngineResult {
        processKey(KeyEvent(char: nil, special: special))
    }
}

private func committed(_ results: [EngineResult]) -> String {
    results.compactMap { if case .commit(let t, _) = $0 { return t } else { return nil } }.joined()
}

private func committed(_ r: EngineResult) -> String? {
    if case .commit(let t, _) = r { return t }
    return nil
}

// MARK: - CodeTable

final class CodeTableTests: XCTestCase {
    /// Regression: the lexicographic window (limit×4) used to be truncated
    /// before ranking, so 2-key codes sorting after many `aa*` codes were lost.
    func testShortCodesSurviveLargePrefixRange() {
        var entries: [Entry] = []
        for i in 0..<1000 {
            entries.append(Entry(text: "x\(i)", code: "aa" + String(format: "%02d", i % 100) + "\(i)", weight: 1))
        }
        entries.append(Entry(text: "目标", code: "az", weight: 1))
        let table = CodeTable(name: "t", entries: entries)
        let hits = table.lookup(prefix: "a", limit: 10)
        XCTAssertEqual(hits.first?.text, "目标")
    }

    func testRankingExactThenShorterThenWeight() {
        let table = CodeTable(name: "t", entries: [
            Entry(text: "long", code: "abc", weight: 100),
            Entry(text: "lo", code: "ab", weight: 1),
            Entry(text: "hi", code: "ab", weight: 9),
            Entry(text: "exact", code: "a", weight: 0),
            Entry(text: "other", code: "b", weight: 50),
        ])
        XCTAssertEqual(table.lookup(prefix: "a").map(\.text), ["exact", "hi", "lo", "long"])
        XCTAssertEqual(table.lookup(prefix: "a", limit: 2).map(\.text), ["exact", "hi"])
        XCTAssertTrue(table.lookup(prefix: "c").isEmpty)
    }
}

// MARK: - Engine

final class EngineTests: XCTestCase {
    func testAutoSelectUniqueFourKeyCode() {
        let e = makeEngine()
        XCTAssertEqual(committed(e.type("abcd")), "戒")
    }

    func testNoAutoSelectWithRivals() {
        let e = makeEngine()
        XCTAssertEqual(committed(e.type("abce")), "")
        XCTAssertEqual(e.currentState().candidates.prefix(2).map(\.text), ["甲", "乙"])
    }

    func testApostropheMidCompositionCommitsAndEntersEnglish() {
        let e = makeEngine()
        let r = e.type("ka'")
        XCTAssertEqual(committed(r), "中")
        XCTAssertTrue(e.currentState().isEnglishMode)
    }

    func testApostropheWithTempEnglishDisabledIsNotSwallowed() {
        let e = makeEngine { $0.enableTempEnglish = false }
        guard case .passthrough = e.processKey(KeyEvent(char: "'")) else {
            return XCTFail("empty-buffer ' must pass through")
        }
        XCTAssertEqual(committed(e.type("ka'")), "中'")
    }

    func testCapitalLetterWhileComposingCommitsTopThenLetter() {
        let e = makeEngine()
        XCTAssertEqual(committed(e.type("kaB")), "中B")
        XCTAssertEqual(e.currentState().preedit, "")
    }

    func testEnglishPhrasePunctuationKeepsWholePhrase() {
        let e = makeEngine()
        e.type("'good")
        _ = e.press(.space)
        XCTAssertEqual(committed(e.type("morning,")), "good morning,")
    }

    func testEnglishAcceptsCapitals() {
        let e = makeEngine()
        e.type("'Hi")
        XCTAssertEqual(e.currentState().preedit, "'Hi")
        XCTAssertEqual(committed(e.press(.enter)), "Hi")
    }

    func testEnterInPinyinModeStripsPrefix() {
        let e = makeEngine()
        e.type("izho")
        XCTAssertEqual(committed(e.press(.enter)), "zho")
    }

    func testRecognizerKeepsUrlLiteral() {
        let e = makeEngine()
        e.type("www.a1-B")
        let s = e.currentState()
        XCTAssertTrue(s.isRawMode)
        XCTAssertTrue(s.keepsPreeditWithoutCandidates)
        XCTAssertEqual(s.preedit, "www.a1-B")
        XCTAssertEqual(committed(e.press(.space)), "www.a1-B")
    }

    func testArrowRightMovesHighlight() {
        let e = makeEngine()
        e.type("a")
        _ = e.press(.arrowRight)
        XCTAssertEqual(e.currentState().highlightedIndex, 1)
        _ = e.press(.arrowLeft)
        XCTAssertEqual(e.currentState().highlightedIndex, 0)
    }

    func testGb2312ToggleAppliesLive() {
        let e = makeEngine()
        e.type("k")
        XCTAssertFalse(e.currentState().candidates.contains { $0.text == "䶮" })
        XCTAssertTrue(e.currentState().candidates.contains { $0.text == "①" })
        e.reset()
        e.config.enableGb2312 = false
        e.type("k")
        XCTAssertTrue(e.currentState().candidates.contains { $0.text == "䶮" })
    }

    func testCandidateCountIsClamped() {
        let e = makeEngine { $0.candidateCount = 0 }
        XCTAssertEqual(e.config.candidateCount, 1)
        e.config.candidateCount = 50
        XCTAssertEqual(e.config.candidateCount, 9)
    }

    func testAnnotationModes() {
        let e = makeEngine()
        e.type("ka")
        XCTAssertEqual(e.currentState().candidates.first?.annotation, "ka")

        e.reset(); e.config.annotation = .none
        e.type("ka")
        XCTAssertEqual(e.currentState().candidates.first?.annotation, "")

        e.reset(); e.config.annotation = .pinyin
        e.type("ka")
        XCTAssertEqual(e.currentState().candidates.first?.annotation, "zhong")

        e.reset(); e.config.annotation = .both
        e.type("ka")
        XCTAssertEqual(e.currentState().candidates.first?.annotation, "ka zhong")
    }

    /// 反查: pinyin candidates show the word's shortest cqlb code.
    func testPinyinReverseLookupShowsCqlbCode() {
        let e = makeEngine()
        e.type("izhong")
        let first = e.currentState().candidates.first
        XCTAssertEqual(first?.text, "中")
        XCTAssertEqual(first?.annotation, "ka")
    }

    /// Annotation must not affect auto-select, which keys off `code`.
    func testAutoSelectIndependentOfAnnotation() {
        let e = makeEngine { $0.annotation = .none }
        XCTAssertEqual(committed(e.type("abcd")), "戒")
    }
}

// MARK: - GB2312

final class Gb2312FilterTests: XCTestCase {
    func testExactRepertoire() {
        XCTAssertEqual(Gb2312Filter.hanziCount, 6763)
        let f = Gb2312Filter(enabled: true)
        XCTAssertTrue(f.accepts("中国"))
        XCTAssertFalse(f.accepts("䶮"))   // Ext A
        XCTAssertFalse(f.accepts("喆"))   // URO but not GB2312
        XCTAssertTrue(f.accepts("①★→ abc"))
    }
}

// MARK: - Config

final class ConfigTests: XCTestCase {
    func testMissingKeysKeepOtherFields() {
        let json = #"{"appearance":{"fontSize":20},"functions":{"tempPinyin":false}}"#
        let cfg = ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(cfg.appearance.fontSize, 20)
        XCTAssertEqual(cfg.appearance.candidateCount, Config.Appearance().candidateCount)
        XCTAssertFalse(cfg.functions.tempPinyin)
        XCTAssertEqual(cfg.shortcuts, Config.Shortcuts())
    }

    func testUnknownEnumValueOnlyResetsThatField() {
        let json = #"{"appearance":{"layout":"diagonal","fontSize":18}}"#
        let cfg = ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(cfg.appearance.layout, .horizontal)
        XCTAssertEqual(cfg.appearance.fontSize, 18)
    }

    func testLegacyShortcutStringsDecode() {
        let json = #"{"shortcuts":{"toggleChineseEnglish":"option_space","clearBuffer":"escape"}}"#
        let cfg = ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(cfg.shortcuts.toggleChineseEnglish, .optionSpace)
        XCTAssertEqual(cfg.shortcuts.shiftTap, .both)
    }

    func testRoundTrip() throws {
        var cfg = Config()
        cfg.shortcuts.shiftTap = .left
        cfg.functions.reverseLookupDisplay = .both
        let data = try JSONEncoder().encode(cfg)
        XCTAssertEqual(ConfigStore.decode(data), cfg)
    }
}

// MARK: - Binary cache

final class BinaryCacheTests: XCTestCase {
    func testFingerprintInvalidatesOnOptionsAndContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cqlb-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("t.dict.yaml")
        try "name: t\n...\n工\ta\t1\n".write(to: src, atomically: true, encoding: .utf8)
        let cache = dir.appendingPathComponent(DictLoader.cacheFileName(for: src))

        XCTAssertFalse(try DictLoader.loadCached(source: src, cache: cache).fromCache)
        XCTAssertTrue(try DictLoader.loadCached(source: src, cache: cache).fromCache)

        // Different options → miss.
        let opts = DictLoadOptions(maxEntries: 1)
        XCTAssertFalse(try DictLoader.loadCached(source: src, cache: cache, options: opts).fromCache)

        // Content change with an OLDER mtime (pkg install) → still a miss.
        _ = try DictLoader.loadCached(source: src, cache: cache)
        try "name: t\n...\n工\ta\t1\n式\tab\t1\n".write(to: src, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: src.path)
        let r = try DictLoader.loadCached(source: src, cache: cache)
        XCTAssertFalse(r.fromCache)
        XCTAssertEqual(r.table.count, 2)
    }
}

// MARK: - Second-pass regressions

final class EngineRegressionTests: XCTestCase {
    /// Regression: `reset()` after each commit cleared the paired-quote
    /// state, so the closing quote never appeared.
    func testPairedQuotesSurviveCommits() {
        let e = makeEngine()
        var out = committed(e.type("\""))
        out += committed(e.type("ka"))
        out += committed([e.press(.space)])
        out += committed(e.type("\""))
        XCTAssertEqual(out, "\u{201C}中\u{201D}")
    }

    /// Function keys arrive as private-use scalars and must never be
    /// committed as text.
    func testFunctionKeyScalarIsNotCommitted() {
        let e = makeEngine()
        e.type("ka")
        guard case .passthrough = e.processKey(KeyEvent(char: "\u{F728}")) else {
            return XCTFail("forward-delete scalar must pass through")
        }
        XCTAssertEqual(e.currentState().preedit, "ka")
    }

    func testReplaceMainTakesEffectAndRefreshesReverseIndex() {
        let e = makeEngine()
        let merged = e.resources.main.merging([Entry(text: "种", code: "kq", weight: 0)])
        e.replaceMain(merged)
        e.type("kq")
        XCTAssertEqual(e.currentState().candidates.first?.text, "种")
        e.reset()
        e.type("izhong")
        XCTAssertEqual(e.currentState().candidates.first { $0.text == "种" }?.annotation, "kq")
    }
}

final class UserDictTests: XCTestCase {
    private let stems: [Character: String] = [
        "中": "zgx", "国": "gghv", "共": "gjx", "产": "cl", "党": "dkr",
        "华": "hx", "人": "rr", "民": "mn", "和": "hk",
    ]
    private func stem(_ c: Character) -> String? { stems[c] }

    func testEncoderRules() {
        XCTAssertEqual(WordEncoder.encode("中国", stem: stem), "zggg")
        XCTAssertEqual(WordEncoder.encode("共产党", stem: stem), "gjcd")
        XCTAssertEqual(WordEncoder.encode("中华人民共和国", stem: stem), "zhrg")
        // Punctuation takes no part in the encoding.
        XCTAssertEqual(WordEncoder.encode("中，国", stem: stem), "zggg")
        XCTAssertNil(WordEncoder.encode("中", stem: stem))
        XCTAssertNil(WordEncoder.encode("中？", stem: stem))
    }

    func testParse() {
        let text = """
        ---
        name: x
        ...
        # comment
        例壹\tdhsl
        例贰\tdhsl\t2
        中国
        无法编码
        #停用\tabcd
        """
        let r = UserDict.parse(text: text, stem: stem)
        XCTAssertEqual(r.entries, [
            Entry(text: "例壹", code: "dhsl", weight: 0),
            Entry(text: "例贰", code: "dhsl", weight: 2),
            Entry(text: "中国", code: "zggg", weight: 0),
        ])
        XCTAssertEqual(r.skipped, ["无法编码"])
    }

    func testTemplateParsesToNothing() {
        XCTAssertTrue(UserDict.parse(text: UserDict.template, stem: stem).entries.isEmpty)
    }

    func testMergeRanking() {
        let main = CodeTable(name: "m", entries: [
            Entry(text: "原", code: "dhsl", weight: 1),
            Entry(text: "前", code: "dhsk", weight: 1),
        ])
        let merged = main.merging([
            Entry(text: "后置", code: "dhsl", weight: 0),
            Entry(text: "前置", code: "dhsl", weight: 2),
            Entry(text: "原", code: "dhsl", weight: 5),      // duplicate of a main entry
        ])
        XCTAssertEqual(merged.lookup(prefix: "dhsl").map(\.text), ["前置", "原", "后置"])
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged.lookup(prefix: "dhs").map(\.text), ["前置", "前", "原", "后置"])
    }

    func testStemTableParse() {
        let yaml = "name: t\n...\n安\ta\t1\tao,z\n安\tao\t1\tao,z\n乙\tia\t1\n乙\tyz\t1\n乙\tyzbk\t1\n词组\tabcd\t1\n"
        let stems = StemTable.parse(yaml)
        XCTAssertEqual(stems["安"], "ao,z")
        XCTAssertEqual(stems["乙"], "yzbk")
        XCTAssertEqual(stems.count, 2)
    }
}

/// Cross-check the encoder and stem extraction against the shipped table:
/// re-encode its multi-character words and compare with their real codes.
final class RealDictEncoderTests: XCTestCase {
    func testAutoEncodingAgreesWithShippedTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dicts/cqlb.dict.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("Dicts/cqlb.dict.yaml not available")
        }
        let stems = StemTable.parse(text)
        XCTAssertGreaterThan(stems.count, 6000)

        let table = try DictLoader.parse(text: text, sourceName: "cqlb")
        var byLength: [Int: (total: Int, match: Int)] = [:]
        var codesByWord: [String: Set<String>] = [:]
        for e in table.allEntries() where e.text.count >= 2 && e.code.count == 4 {
            codesByWord[e.text, default: []].insert(e.code)
        }
        for (word, codes) in codesByWord {
            guard let auto = WordEncoder.encode(word, stem: { stems[$0] }) else { continue }
            let bucket = min(word.count, 4)
            byLength[bucket, default: (0, 0)].total += 1
            if codes.contains(auto) { byLength[bucket]!.match += 1 }
        }
        for (len, r) in byLength.sorted(by: { $0.key < $1.key }) {
            let rate = Double(r.match) / Double(max(r.total, 1))
            print("encoder agreement, \(len)\(len == 4 ? "+" : "")-char words: \(r.match)/\(r.total) = \(String(format: "%.1f%%", rate * 100))")
            XCTAssertGreaterThan(rate, 0.9, "\(len)-char words")
        }
    }
}

// MARK: - Schemes

final class SchemeTests: XCTestCase {
    private let table: [Entry] = [
        Entry(text: "中", code: "zg", weight: 1),
        Entry(text: "中国", code: "zggg", weight: 1),
        Entry(text: "也", code: "ua", weight: 1),
        Entry(text: "％", code: "vb", weight: 1),
        Entry(text: "℃", code: "vc", weight: 1),
        Entry(text: "°", code: "vc", weight: 1),
        Entry(text: "群", code: "inih", weight: 1),
        Entry(text: "群", code: "qvkd", weight: 1),
    ]

    private func cqyx(_ configure: (inout EngineConfig) -> Void = { _ in }) -> Engine {
        makeEngine(main: table) { $0.scheme = .cqyx; configure(&$0) }
    }

    func testSemicolonStartsEnglishInCqyx() {
        let e = cqyx()
        e.type(";he")
        XCTAssertTrue(e.currentState().isEnglishMode)
        XCTAssertEqual(e.currentState().candidates.first?.text, "help")
        XCTAssertEqual(committed(e.press(.enter)), "he")
    }

    func testSemicolonIsPunctuationWhenEnglishDisabledInCqyx() {
        let e = cqyx { $0.enableTempEnglish = false }
        XCTAssertEqual(committed(e.type(";")), "\u{FF1B}")
        XCTAssertEqual(committed(e.type("zg;")), "中\u{FF1B}")
    }

    /// `, . /` are not code characters in 音形: they punctuate immediately.
    func testCommaPunctuatesWhileComposingInCqyx() {
        let e = cqyx()
        XCTAssertEqual(committed(e.type("zg,")), "中\u{FF0C}")
        XCTAssertEqual(e.currentState().preedit, "")
    }

    func testApostropheIsLiteralInCqyx() {
        let e = cqyx()
        XCTAssertEqual(committed(e.type("zg'")), "中'")
    }

    func testShortUVCodeAutoSelectsOnlyInCqyxAndOnlyWhenUnique() {
        XCTAssertEqual(committed(cqyx().type("ua")), "也")
        XCTAssertEqual(committed(cqyx().type("vb")), "％")
        // Two entries share `vc`: stop and let the user choose.
        let rivals = cqyx()
        XCTAssertEqual(committed(rivals.type("vc")), "")
        XCTAssertEqual(rivals.currentState().candidates.count, 2)
        // 两笔 has no such rule.
        let lb = makeEngine(main: table)
        XCTAssertEqual(committed(lb.type("ua")), "")
    }

    func testFourKeyAutoSelectInCqyx() {
        XCTAssertEqual(committed(cqyx().type("zggg")), "中国")
    }

    func testSwitchingSchemeAbandonsComposition() {
        let e = makeEngine(main: table)
        e.type("zg")
        e.config.scheme = .cqyx
        XCTAssertEqual(e.currentState().preedit, "")
    }

    /// `i` + 2 or more keys is pinyin mode, so an `i…` table code is not
    /// typeable and must not be offered as the reverse-lookup answer.
    func testReverseLookupSkipsUntypeableICodes() {
        let e = makeEngine(
            main: table,
            pinyin: [Entry(text: "群", code: "iqun", weight: 0)]
        )
        e.type("iqun")
        XCTAssertEqual(e.currentState().candidates.first?.annotation, "qvkd")
    }

    func testSchemeConfigDecoding() {
        XCTAssertEqual(ConfigStore.decode(Data(#"{"scheme":"cqyx"}"#.utf8)).scheme, .cqyx)
        XCTAssertEqual(ConfigStore.decode(Data(#"{"scheme":"bogus"}"#.utf8)).scheme, .cqlb)
        XCTAssertEqual(ConfigStore.decode(Data("{}".utf8)).scheme, .cqlb)
        XCTAssertNotEqual(UserDict.url(for: .cqlb), UserDict.url(for: .cqyx))
    }
}

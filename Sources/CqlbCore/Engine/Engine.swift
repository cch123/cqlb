import Foundation

/// Configuration passed into the engine. Mirrors the JSON config file.
public struct EngineConfig: Sendable, Equatable {
    public var candidateCount: Int
    public var maxCodeLength: Int
    public var autoSelect: Bool
    public var enableTempEnglish: Bool
    public var enableTempPinyin: Bool
    public var enableEmoji: Bool
    public var enableGb2312: Bool
    public var enableRecognizer: Bool
    public var annotation: Annotation
    public var scheme: Scheme

    /// What to show next to each candidate.
    ///
    /// - `code`: the cqlb code. For main-table candidates that is the entry's
    ///   own code; for pinyin reverse-lookup candidates it is the shortest
    ///   cqlb code of the word (the point of 反查: learn how to type it).
    /// - `pinyin`: the word's pinyin from the ipinyin table.
    public enum Annotation: Sendable, Equatable {
        case none, code, pinyin, both
    }

    public static let `default` = EngineConfig(
        candidateCount: 6,
        maxCodeLength: 4,
        autoSelect: true,
        enableTempEnglish: true,
        enableTempPinyin: true,
        enableEmoji: true,
        enableGb2312: true,
        enableRecognizer: true,
        annotation: .code,
        scheme: .cqlb
    )

    public init(
        candidateCount: Int,
        maxCodeLength: Int,
        autoSelect: Bool,
        enableTempEnglish: Bool,
        enableTempPinyin: Bool,
        enableEmoji: Bool,
        enableGb2312: Bool,
        enableRecognizer: Bool,
        annotation: Annotation = .code,
        scheme: Scheme = .cqlb
    ) {
        self.candidateCount = candidateCount
        self.maxCodeLength = maxCodeLength
        self.autoSelect = autoSelect
        self.enableTempEnglish = enableTempEnglish
        self.enableTempPinyin = enableTempPinyin
        self.enableEmoji = enableEmoji
        self.enableGb2312 = enableGb2312
        self.enableRecognizer = enableRecognizer
        self.annotation = annotation
        self.scheme = scheme
    }
}

/// Resources handed to the engine at init time. All dictionaries are preloaded.
public struct EngineResources: Sendable {
    public var main: CodeTable
    public var pinyin: CodeTable?
    public var english: CodeTable?
    public var emoji: EmojiDict

    public init(main: CodeTable, pinyin: CodeTable?, english: CodeTable?, emoji: EmojiDict) {
        self.main = main
        self.pinyin = pinyin
        self.english = english
        self.emoji = emoji
    }
}

/// One semantic key event as seen by the engine. The IMKit shell translates
/// NSEvents into this at call time.
public struct KeyEvent: Sendable {
    public enum Special: Sendable {
        case backspace, enter, escape, space, tab
        case pageUp, pageDown, arrowUp, arrowDown, arrowLeft, arrowRight
    }
    public let char: Character?     // printable char if any
    public let special: Special?    // non-printable action
    public let modifiers: Modifiers

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let shift   = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option  = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public init(char: Character?, special: Special? = nil, modifiers: Modifiers = []) {
        self.char = char
        self.special = special
        self.modifiers = modifiers
    }
}

/// One candidate as rendered in the UI.
///
/// `code` is the dictionary code the candidate was matched by and drives
/// engine logic (auto-select, rival detection). `annotation` is display-only
/// text derived from the annotation setting and may be empty.
public struct DisplayCandidate: Sendable, Hashable {
    public let text: String
    public let code: String
    public let annotation: String
    public let source: Candidate.Source

    public init(text: String, code: String, annotation: String, source: Candidate.Source) {
        self.text = text
        self.code = code
        self.annotation = annotation
        self.source = source
    }
}

/// What the engine wants the shell to do after processing a key.
public enum EngineResult: Sendable {
    /// The key did not belong to us; let the system handle it.
    case passthrough
    /// Engine state changed; re-render the composition window.
    case update(EngineState)
    /// Emit this text to the client and clear composition state.
    case commit(String, state: EngineState)
}

/// Snapshot of the composition window for the shell to render.
public struct EngineState: Sendable {
    public var preedit: String                       // what shows inline
    public var candidates: [DisplayCandidate]        // page to display
    public var highlightedIndex: Int                 // inside `candidates`
    public var pageIndex: Int
    public var hasPrevPage: Bool
    public var hasNextPage: Bool
    public var isPinyinMode: Bool
    public var isEnglishMode: Bool
    /// Buffer matched a recognizer pattern (URL / e-mail) and is passed
    /// through verbatim; there are intentionally no candidates.
    public var isRawMode: Bool

    /// Modes in which an empty candidate list is a valid, visible state
    /// (the user is still typing and can backspace), as opposed to main
    /// mode where "no candidates" means an invalid code.
    public var keepsPreeditWithoutCandidates: Bool {
        isPinyinMode || isEnglishMode || isRawMode
    }

    public static let empty = EngineState(
        preedit: "",
        candidates: [],
        highlightedIndex: 0,
        pageIndex: 0,
        hasPrevPage: false,
        hasNextPage: false,
        isPinyinMode: false,
        isEnglishMode: false,
        isRawMode: false
    )
}

public final class Engine {
    /// Assigning a new config takes effect immediately, including the
    /// GB2312 filter and recognizer, which were previously frozen at init.
    public var config: EngineConfig {
        didSet {
            config.candidateCount = min(max(config.candidateCount, 1), 9)
            if config.enableGb2312 != gb2312.isEnabled {
                gb2312 = Gb2312Filter(enabled: config.enableGb2312)
            }
            if config.enableRecognizer != recognizer.isEnabled {
                recognizer = Recognizer(enabled: config.enableRecognizer)
            }
            // Codes of one scheme mean nothing in the other.
            if config.scheme != oldValue.scheme { reset() }
            if config != oldValue { warmIndexes() }
        }
    }
    public private(set) var resources: EngineResources
    private let punctuator: Punctuator
    private var gb2312: Gb2312Filter
    private var recognizer: Recognizer

    private var buffer: String = ""
    private var allCandidates: [DisplayCandidate] = []
    private var pageIndex: Int = 0
    private var highlightedIndex: Int = 0

    /// word → shortest cqlb code. Built on first use; dropped by `replaceMain`.
    private var codeIndexStorage: [String: String]?
    private var codeIndex: [String: String] {
        if let cached = codeIndexStorage { return cached }
        let built = Self.buildCodeIndex(resources.main)
        codeIndexStorage = built
        return built
    }
    /// word → pinyin reading(s). Built on first use.
    private lazy var pinyinIndex: [String: String] = Self.buildPinyinIndex(resources.pinyin)

    public init(resources: EngineResources, config: EngineConfig = .default) {
        self.resources = resources
        var cfg = config
        cfg.candidateCount = min(max(cfg.candidateCount, 1), 9)
        self.config = cfg
        self.punctuator = Punctuator()
        self.gb2312 = Gb2312Filter(enabled: cfg.enableGb2312)
        self.recognizer = Recognizer(enabled: cfg.enableRecognizer)
        warmIndexes()
    }

    // MARK: - Public API

    public func currentState() -> EngineState { state() }

    /// Clear the composition. Deliberately leaves the punctuator's paired
    /// quote state alone: `reset()` runs after every commit, and clearing the
    /// state there made `"你好"` come out as “你好“ (the closing quote never
    /// appeared once any text was committed in between).
    public func reset() {
        buffer = ""
        allCandidates = []
        pageIndex = 0
        highlightedIndex = 0
    }

    /// Swap the main code table (user dictionary reloaded). Abandons any
    /// in-flight composition, whose candidates came from the old table.
    public func replaceMain(_ table: CodeTable) {
        reset()
        resources.main = table
        codeIndexStorage = nil
        warmIndexes()
    }

    public func processKey(_ event: KeyEvent) -> EngineResult {
        // Modifier combos we don't handle at all.
        if event.modifiers.contains(.command) || event.modifiers.contains(.control) {
            return .passthrough
        }

        if let special = event.special {
            return handleSpecial(special)
        }

        guard let char = event.char else { return .passthrough }

        // Raw mode (URL / e-mail). Checked first so that `.`, `@`, `:`,
        // digits and capitals extend the literal instead of being taken as
        // punctuation, candidate selection, or a commit trigger.
        if !buffer.isEmpty,
           Self.isPrintableASCII(char),
           recognizer.match(buffer + String(char)) != nil
        {
            buffer.append(char)
            allCandidates = []
            pageIndex = 0
            highlightedIndex = 0
            return .update(state())
        }

        // Digit selection. While a composition is active, `1`..`9` pick the
        // corresponding candidate on the current page. cqlb's speller alphabet
        // contains no digits, so this can never clash with a code character.
        if !buffer.isEmpty,
           !allCandidates.isEmpty,
           let ascii = char.asciiValue,
           ascii >= UInt8(ascii: "1"),
           ascii <= UInt8(ascii: "9")
        {
            let slot = Int(ascii - UInt8(ascii: "1"))
            return selectCandidate(at: slot)
        }

        // Page navigation with `-` and `=` keys when candidates are showing.
        // Not in temp-English mode, where `-` is part of words.
        if !buffer.isEmpty, !allCandidates.isEmpty, !isEnglishBuffer {
            if char == "-" { return handleSpecial(.pageUp) }
            if char == "=" { return handleSpecial(.pageDown) }
        }

        if isEnglishBuffer {
            return handleEnglishChar(char)
        }

        if buffer.isEmpty {
            return handleCharOnEmptyBuffer(char)
        }

        // Temp-English prefix (`'` in 两笔, `;` in 音形) while composing:
        // commit what we have, then enter temp English. If temp English is
        // unavailable the key is emitted after the commit instead — as
        // punctuation when it has a mapping (`;` → ；), else literally.
        // Previously the `'` was appended to the code, the lookup came back
        // empty and the whole composition was silently discarded.
        if char == englishPrefix {
            let flushed = topCandidateText() ?? displayPreedit()
            reset()
            if englishAvailable {
                buffer = String(englishPrefix)
                recompute()
                return .commit(flushed, state: state())
            }
            let tail = punctuator.translate(char, bufferEmpty: true, codePunctuation: codePunctuation)
                ?? String(char)
            return .commit(flushed + tail, state: state())
        }

        // Non-overlap punctuation: flush the top candidate, then emit the
        // Chinese punctuation after it.
        if let punctOut = punctuator.translate(char, bufferEmpty: false, codePunctuation: codePunctuation) {
            let flushed = topCandidateText() ?? displayPreedit()
            reset()
            return .commit(flushed + punctOut, state: state())
        }

        if isSpellerChar(char) {
            return extendComposition(with: char)
        }

        // Any other printable key while composing (capital letters, digits
        // with no candidates, Option-symbols …): commit the top candidate and
        // the key's own text. Passing the key through instead would let the
        // client insert it next to still-marked preedit text.
        if Self.isPrintable(char) {
            let flushed = topCandidateText() ?? displayPreedit()
            reset()
            return .commit(flushed + String(char), state: state())
        }
        return .passthrough
    }

    public func selectCandidate(at index: Int) -> EngineResult {
        let pageStart = pageIndex * config.candidateCount
        let absolute = pageStart + index
        guard index >= 0, absolute < allCandidates.count else {
            return .update(state())
        }
        let chosen = allCandidates[absolute]

        // English mode: replace the last word in the buffer with the chosen
        // completion, keeping previous words. User continues building a phrase.
        if isEnglishBuffer {
            let parts = buffer.split(separator: " ", omittingEmptySubsequences: false)
            if parts.count > 1 {
                var newParts = Array(parts.dropLast())
                newParts.append(Substring(chosen.text))
                buffer = newParts.joined(separator: " ") + " "
            } else {
                buffer = String(englishPrefix) + chosen.text + " "
            }
            recompute()
            return .update(state())
        }

        reset()
        return .commit(chosen.text, state: state())
    }

    // MARK: - Character handling

    private func handleCharOnEmptyBuffer(_ char: Character) -> EngineResult {
        // The temp-English prefix starts that mode when it is usable. This
        // must precede punctuation: 音形's prefix `;` also maps to ；.
        if char == englishPrefix && englishAvailable {
            return extendComposition(with: char)
        }
        // `'` with temp English unavailable: let the literal apostrophe
        // through instead of swallowing it.
        if char == "'" && englishPrefix == "'" {
            return .passthrough
        }
        if let punctOut = punctuator.translate(char, bufferEmpty: true, codePunctuation: codePunctuation) {
            return .commit(punctOut, state: state())
        }
        if isSpellerChar(char) {
            return extendComposition(with: char)
        }
        return .passthrough
    }

    /// Temp-English (`'`-prefixed) composition. Letters, digits, `'` and
    /// `-` build the current word; other printable ASCII ends the phrase and
    /// is committed after it verbatim (English text wants ASCII punctuation,
    /// not full-width Chinese punctuation).
    private func handleEnglishChar(_ char: Character) -> EngineResult {
        if let a = char.asciiValue,
           (a >= 0x30 && a <= 0x39) || (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A)
            || char == "'" || char == "-"
        {
            buffer.append(char)
            recompute()
            return .update(state())
        }
        if Self.isPrintable(char) {
            let out = englishPhrase() + String(char)
            reset()
            return .commit(out, state: state())
        }
        return .passthrough
    }

    /// Append a speller character to a main / pinyin composition.
    private func extendComposition(with char: Character) -> EngineResult {
        // Lookahead for alphabet-overlap punctuation (`,./;`): if appending
        // this char would eliminate all candidates, don't eat it into the
        // buffer. Instead, commit the current top candidate (if any) and
        // emit the char as Chinese punctuation. This is the behavior users
        // expect when typing "iwoshi," — the comma should punctuate, not
        // poison the pinyin composition.
        if isOverlapPunct(char) && !buffer.isEmpty {
            let probe = query(buffer + String(char))
            if probe.isEmpty {
                let prevTop = topCandidateText() ?? displayPreedit()
                reset()
                if let punctOut = punctuator.translate(char, bufferEmpty: true, codePunctuation: codePunctuation) {
                    return .commit(prevTop + punctOut, state: state())
                }
                return .commit(prevTop + String(char), state: state())
            }
        }

        // When buffer is already at max code length and there are
        // candidates showing (rival/ambiguous case), commit the top
        // candidate and start a new buffer with this new character.
        // Only applies to cqlb main mode — pinyin reverse lookup
        // (`i`-prefix) allows codes longer than the schema's 4-char maximum.
        if buffer.count >= config.maxCodeLength,
           !allCandidates.isEmpty,
           !isInPinyinMode(),
           let first = allCandidates.first
        {
            let text = first.text
            reset()
            buffer.append(char)
            recompute()
            return .commit(text, state: state())
        }

        buffer.append(char)
        recompute()

        // Auto-select: only for cqlb main mode, only when the buffer has
        // reached the schema's max code length, and only when the top
        // candidate's code is an EXACT match for the current buffer.
        // Skip auto-select when multiple candidates share the same exact
        // code — let the user pick from the candidate list instead.
        if config.autoSelect,
           buffer.count == config.maxCodeLength,
           let first = allCandidates.first,
           first.source == .main,
           first.code == buffer
        {
            let hasRival = allCandidates.dropFirst().contains {
                $0.source == .main && $0.code == buffer
            }
            if !hasRival {
                let text = first.text
                reset()
                return .commit(text, state: state())
            }
        }

        // 音形: a two-key `u?` / `v?` code commits by itself when it is the
        // only match (schema `auto_select_pattern: (^[uv].$)|^.{4}$`).
        if config.autoSelect,
           config.scheme.autoSelectsShortUV,
           buffer.count == 2,
           let lead = buffer.first, lead == "u" || lead == "v"
        {
            let mains = allCandidates.filter { $0.source == .main }
            if mains.count == 1, mains[0].code == buffer {
                let text = mains[0].text
                reset()
                return .commit(text, state: state())
            }
        }

        // auto_clear: max_length — if we reached max code length but have
        // NO candidates (invalid code), silently discard the buffer. This
        // matches Rime's behavior: the user never sees "no candidates" for
        // full-length codes.
        if buffer.count >= config.maxCodeLength,
           allCandidates.isEmpty,
           !isInPinyinMode()
        {
            reset()
            return .update(state())
        }

        return .update(state())
    }

    // MARK: - Special keys

    private func handleSpecial(_ special: KeyEvent.Special) -> EngineResult {
        switch special {
        case .backspace:
            if buffer.isEmpty { return .passthrough }
            buffer.removeLast()
            if buffer.isEmpty {
                reset()
                return .update(state())
            }
            if recognizer.match(buffer) != nil {
                allCandidates = []
                pageIndex = 0
                highlightedIndex = 0
            } else {
                recompute()
            }
            return .update(state())

        case .space:
            if buffer.isEmpty { return .passthrough }
            // English mode: space appends to buffer (building a phrase).
            // Enter commits the whole thing.
            if isEnglishBuffer {
                buffer.append(" ")
                recompute()
                return .update(state())
            }
            // Recognizer bypass commits buffer verbatim on space.
            if recognizer.match(buffer) != nil {
                let out = buffer
                reset()
                return .commit(out, state: state())
            }
            if allCandidates.isEmpty {
                // e.g. pinyin with no match: commit what was typed rather
                // than swallowing the space with no visible effect.
                let out = displayPreedit()
                reset()
                return .commit(out, state: state())
            }
            return selectCandidate(at: highlightedIndex)

        case .enter:
            if buffer.isEmpty { return .passthrough }
            // Commit the typed text verbatim, minus mode prefixes:
            // `'` (temp English) and `i` (pinyin reverse lookup).
            let out: String
            if isEnglishBuffer {
                out = englishPhrase()
            } else if isInPinyinMode() {
                out = String(buffer.dropFirst())
            } else {
                out = buffer
            }
            reset()
            return .commit(out, state: state())

        case .escape:
            if buffer.isEmpty { return .passthrough }
            reset()
            return .update(state())

        case .arrowDown, .arrowRight, .tab:
            if allCandidates.isEmpty {
                if !buffer.isEmpty { return .update(state()) }
                return .passthrough
            }
            moveHighlight(by: 1)
            return .update(state())

        case .arrowUp, .arrowLeft:
            if allCandidates.isEmpty {
                if !buffer.isEmpty { return .update(state()) }
                return .passthrough
            }
            moveHighlight(by: -1)
            return .update(state())

        case .pageDown:
            if !allCandidates.isEmpty, (pageIndex + 1) * config.candidateCount < allCandidates.count {
                pageIndex += 1
                highlightedIndex = 0
                return .update(state())
            }
            if !buffer.isEmpty { return .update(state()) }
            return .passthrough

        case .pageUp:
            if pageIndex > 0 {
                pageIndex -= 1
                highlightedIndex = 0
                return .update(state())
            }
            if !buffer.isEmpty { return .update(state()) }
            return .passthrough
        }
    }

    /// Move the highlight one slot, crossing page boundaries.
    private func moveHighlight(by delta: Int) {
        let pageSize = config.candidateCount
        let pageStart = pageIndex * pageSize
        let pageCandCount = min(pageStart + pageSize, allCandidates.count) - pageStart
        if delta > 0 {
            if highlightedIndex + 1 < pageCandCount {
                highlightedIndex += 1
            } else if (pageIndex + 1) * pageSize < allCandidates.count {
                pageIndex += 1
                highlightedIndex = 0
            }
        } else {
            if highlightedIndex > 0 {
                highlightedIndex -= 1
            } else if pageIndex > 0 {
                pageIndex -= 1
                let start = pageIndex * pageSize
                let end = min(start + pageSize, allCandidates.count)
                highlightedIndex = (end - start) - 1
            }
        }
    }

    // MARK: - Query

    private func recompute() {
        pageIndex = 0
        highlightedIndex = 0
        allCandidates = query(buffer)
    }

    private func query(_ input: String) -> [DisplayCandidate] {
        guard let first = input.first else { return [] }

        // Prefix dispatch.
        if first == englishPrefix && englishAvailable, let eng = resources.english {
            return queryEnglish(String(input.dropFirst()), dict: eng)
        }
        // Pinyin reverse lookup only kicks in for 3+ character inputs starting
        // with `i`. Short `i`-prefix inputs (`i`, `ib`, `ia`, …) still live in
        // the main cqlb dictionary — they encode single radicals / characters
        // like `有` / `𠃌` / `艹`. This matches Rime's recognizer pattern
        // `^i.[a-z;,./]+$` which requires length >= 3 before tagging as
        // i_reverse_lookup.
        if first == "i",
           input.count >= 3,
           config.enableTempPinyin,
           let py = resources.pinyin
        {
            return queryPinyin(input, dict: py)
        }
        return queryMain(input)
    }

    private var englishAvailable: Bool {
        config.enableTempEnglish && resources.english != nil
    }

    private var isEnglishBuffer: Bool {
        buffer.first == englishPrefix && englishAvailable
    }

    private var englishPrefix: Character { config.scheme.englishPrefix }
    private var codePunctuation: Set<Character> { config.scheme.codePunctuation }

    /// True when the current composition is being handled as pinyin reverse
    /// lookup rather than main cqlb lookup.
    private func isInPinyinMode() -> Bool {
        return buffer.hasPrefix("i")
            && buffer.count >= 3
            && config.enableTempPinyin
            && resources.pinyin != nil
    }

    private func queryMain(_ input: String) -> [DisplayCandidate] {
        let hits = resources.main.lookup(prefix: input, limit: 128)
        var out: [DisplayCandidate] = []
        out.reserveCapacity(hits.count + 8)
        // Skip GB2312 filtering for v-prefix (symbol input) — those entries
        // are specifically symbols that would be wrongly dropped.
        let skipFilter = input.hasPrefix("v")
        for e in hits {
            if !skipFilter && !gb2312.accepts(e.text) { continue }
            out.append(DisplayCandidate(
                text: e.text,
                code: e.code,
                annotation: annotate(text: e.text, code: e.code, pinyin: nil),
                source: .main
            ))
        }
        // Insert emoji suggestions right after the first matching candidate so
        // they land on page 1 rather than trailing the full result set.
        if config.enableEmoji, let first = out.first {
            let emojis = resources.emoji.emojis(for: first.text)
            if !emojis.isEmpty {
                let emojiAnno = config.annotation == .none ? "" : first.text
                let items = emojis.map {
                    DisplayCandidate(text: $0, code: first.code, annotation: emojiAnno, source: .emoji)
                }
                out.insert(contentsOf: items, at: 1)
            }
        }
        return out
    }

    private func queryPinyin(_ input: String, dict: CodeTable) -> [DisplayCandidate] {
        // ipinyin codes already carry the leading `i`, so we query with `input` directly.
        let hits = dict.lookup(prefix: input, limit: 128)
        var out: [DisplayCandidate] = []
        for e in hits {
            if !gb2312.accepts(e.text) { continue }
            // Strip leading `i` for display (xform/^i(.*)/$1/).
            let py = e.code.hasPrefix("i") ? String(e.code.dropFirst()) : e.code
            out.append(DisplayCandidate(
                text: e.text,
                code: e.code,
                annotation: annotate(text: e.text, code: codeIndex[e.text], pinyin: py),
                source: .pinyin
            ))
        }
        return out
    }

    private func queryEnglish(_ input: String, dict: CodeTable) -> [DisplayCandidate] {
        guard !input.isEmpty else { return [] }
        // For multi-word input ("hello world"), only complete the LAST word.
        let lastWord = input.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? input
        guard !lastWord.isEmpty else { return [] }
        let hits = dict.lookup(prefix: lastWord, limit: 32)
        return hits.map {
            DisplayCandidate(text: $0.text, code: $0.code, annotation: "", source: .english)
        }
    }

    /// Build the display annotation for a candidate per `config.annotation`.
    /// `code` / `pinyin` are looked up from the reverse indexes when nil.
    private func annotate(text: String, code: String?, pinyin: String?) -> String {
        switch config.annotation {
        case .none:
            return ""
        case .code:
            return code ?? ""
        case .pinyin:
            return pinyin ?? pinyinIndex[text] ?? ""
        case .both:
            let parts = [code, pinyin ?? pinyinIndex[text]].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }
    }

    // MARK: - Reverse indexes

    private func warmIndexes() {
        // Build indexes the current config will need now, at startup or
        // settings-change time, rather than on the first keystroke.
        if config.enableTempPinyin && (config.annotation == .code || config.annotation == .both) {
            _ = codeIndex
        }
        if config.annotation == .pinyin || config.annotation == .both {
            _ = pinyinIndex
        }
    }

    static func buildCodeIndex(_ table: CodeTable) -> [String: String] {
        var best: [String: (code: String, weight: UInt32)] = [:]
        best.reserveCapacity(table.count / 2)
        for e in table.allEntries() {
            // `i` + 2 or more keys is pinyin reverse lookup, so such codes
            // cannot be typed as table codes; never suggest them.
            if e.code.first == "i" && e.code.utf8.count >= 3 { continue }
            if let cur = best[e.text] {
                let curLen = cur.code.utf8.count, newLen = e.code.utf8.count
                if newLen < curLen || (newLen == curLen && e.weight > cur.weight) {
                    best[e.text] = (e.code, e.weight)
                }
            } else {
                best[e.text] = (e.code, e.weight)
            }
        }
        return best.mapValues(\.code)
    }

    /// At most two distinct readings per word, joined by `/` (e.g. 阿 → a/e).
    static func buildPinyinIndex(_ table: CodeTable?) -> [String: String] {
        guard let table else { return [:] }
        var readings: [String: [String]] = [:]
        for e in table.allEntries() {
            let py = e.code.hasPrefix("i") ? String(e.code.dropFirst()) : e.code
            guard !py.isEmpty else { continue }
            var list = readings[e.text, default: []]
            if list.count < 2 && !list.contains(py) {
                list.append(py)
                readings[e.text] = list
            }
        }
        return readings.mapValues { $0.joined(separator: "/") }
    }

    // MARK: - Helpers

    private func topCandidateText() -> String? { allCandidates.first?.text }

    private func englishPhrase() -> String {
        String(buffer.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func isSpellerChar(_ c: Character) -> Bool {
        // a–z, the scheme's code punctuation (两笔: ; , . /), and the
        // temp-English prefix.
        if let s = c.asciiValue, s >= UInt8(ascii: "a") && s <= UInt8(ascii: "z") { return true }
        return codePunctuation.contains(c) || c == englishPrefix
    }

    private func isOverlapPunct(_ c: Character) -> Bool {
        codePunctuation.contains(c)
    }

    private static func isPrintableASCII(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a > 0x20 && a < 0x7F
    }

    private static func isPrintable(_ c: Character) -> Bool {
        if let a = c.asciiValue { return a > 0x20 && a < 0x7F }
        // AppKit reports function keys (F1…, Home, End, forward delete …) as
        // private-use scalars U+F700–U+F8FF; those are not text.
        return !c.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .privateUse, .format, .unassigned, .surrogate: return true
            default: return false
            }
        }
    }

    private func state() -> EngineState {
        let page = pageIndex
        let pageSize = config.candidateCount
        let start = page * pageSize
        let end = min(start + pageSize, allCandidates.count)
        let slice = start < end ? Array(allCandidates[start..<end]) : []
        return EngineState(
            preedit: displayPreedit(),
            candidates: slice,
            highlightedIndex: highlightedIndex,
            pageIndex: page,
            hasPrevPage: page > 0,
            hasNextPage: end < allCandidates.count,
            isPinyinMode: isInPinyinMode(),
            isEnglishMode: isEnglishBuffer,
            isRawMode: !buffer.isEmpty && recognizer.match(buffer) != nil
        )
    }

    private func displayPreedit() -> String {
        // Rime schema's preedit_format:
        //   xform/^i(.*)/$1/  — strip leading `i` when in pinyin reverse lookup
        //   xform/^v/z/        — replace leading `v` with `z`
        if isInPinyinMode() {
            return String(buffer.dropFirst())
        }
        if buffer.hasPrefix("v") {
            return "z" + buffer.dropFirst()
        }
        return buffer
    }
}

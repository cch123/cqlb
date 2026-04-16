import Foundation

/// Configuration passed into the engine. Mirrors the JSON config file.
public struct EngineConfig: Sendable {
    public var candidateCount: Int
    public var maxCodeLength: Int
    public var autoSelect: Bool
    public var enableTempEnglish: Bool
    public var enableTempPinyin: Bool
    public var enableEmoji: Bool
    public var enableGb2312: Bool
    public var enableRecognizer: Bool

    public static let `default` = EngineConfig(
        candidateCount: 6,
        maxCodeLength: 4,
        autoSelect: true,
        enableTempEnglish: true,
        enableTempPinyin: true,
        enableEmoji: true,
        enableGb2312: true,
        enableRecognizer: true
    )

    public init(
        candidateCount: Int,
        maxCodeLength: Int,
        autoSelect: Bool,
        enableTempEnglish: Bool,
        enableTempPinyin: Bool,
        enableEmoji: Bool,
        enableGb2312: Bool,
        enableRecognizer: Bool
    ) {
        self.candidateCount = candidateCount
        self.maxCodeLength = maxCodeLength
        self.autoSelect = autoSelect
        self.enableTempEnglish = enableTempEnglish
        self.enableTempPinyin = enableTempPinyin
        self.enableEmoji = enableEmoji
        self.enableGb2312 = enableGb2312
        self.enableRecognizer = enableRecognizer
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

/// One candidate as rendered in the UI. Carries annotation text so the shell
/// can display code / pinyin next to the primary word.
public struct DisplayCandidate: Sendable, Hashable {
    public let text: String
    public let annotation: String      // e.g. "aajj" or "nihao"
    public let source: Candidate.Source

    public init(text: String, annotation: String, source: Candidate.Source) {
        self.text = text
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
    public var isPinyinMode: Bool                    // true when in i-prefix reverse lookup

    public static let empty = EngineState(
        preedit: "",
        candidates: [],
        highlightedIndex: 0,
        pageIndex: 0,
        hasPrevPage: false,
        hasNextPage: false,
        isPinyinMode: false
    )
}

public final class Engine {
    public var config: EngineConfig
    public let resources: EngineResources
    private let punctuator: Punctuator
    private let gb2312: Gb2312Filter
    private let recognizer: Recognizer

    private var buffer: String = ""
    private var allCandidates: [DisplayCandidate] = []
    private var pageIndex: Int = 0

    public init(resources: EngineResources, config: EngineConfig = .default) {
        self.resources = resources
        self.config = config
        self.punctuator = Punctuator()
        self.gb2312 = Gb2312Filter(enabled: config.enableGb2312)
        self.recognizer = Recognizer(enabled: config.enableRecognizer)
    }

    // MARK: - Public API

    public func currentState() -> EngineState { state() }

    public func reset() {
        buffer = ""
        allCandidates = []
        pageIndex = 0
        punctuator.reset()
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
        if !buffer.isEmpty {
            if char == "-" && !allCandidates.isEmpty {
                return handleSpecial(.pageUp)
            }
            if char == "=" && !allCandidates.isEmpty {
                return handleSpecial(.pageDown)
            }
        }

        // Punctuation: only when we can consume it cleanly.
        if let punctOut = punctuator.translate(char, bufferEmpty: buffer.isEmpty) {
            if buffer.isEmpty {
                return .commit(punctOut, state: state())
            }
            // Buffer non-empty and char is a pure-punct char (not an alphabet overlap):
            // flush current buffer's top candidate, then emit punctuation after.
            let flushed = topCandidateText() ?? buffer
            reset()
            return .commit(flushed + punctOut, state: state())
        }

        // Alphabetic composition extension.
        if isSpellerChar(char) {
            // Lookahead for alphabet-overlap punctuation (`,./;`): if appending
            // this char would eliminate all candidates, don't eat it into the
            // buffer. Instead, commit the current top candidate (if any) and
            // emit the char as Chinese punctuation. This is the behavior users
            // expect when typing "iwoshi," — the comma should punctuate, not
            // poison the pinyin composition.
            if isOverlapPunct(char) && !buffer.isEmpty {
                let candidate = buffer + String(char)
                let probe = query(candidate)
                if probe.isEmpty {
                    let prevTop = topCandidateText()
                    reset()
                    if let punctOut = punctuator.translate(char, bufferEmpty: true) {
                        return .commit((prevTop ?? "") + punctOut, state: state())
                    }
                    // No punct mapping — fall through to pass so the char reaches
                    // the client literally.
                    return .passthrough
                }
            }

            buffer.append(char)
            recompute()

            // Recognizer bypass (url / email): preedit is shown but no candidates.
            if recognizer.match(buffer) != nil {
                allCandidates = []
                return .update(state())
            }

            // Auto-select: only for cqlb main mode, only when the buffer has
            // reached the schema's max code length, and only when the top
            // candidate's code is an EXACT match for the current buffer.
            if config.autoSelect,
               buffer.count == config.maxCodeLength,
               let first = allCandidates.first,
               first.source == .main,
               first.annotation == buffer
            {
                let text = first.text
                reset()
                return .commit(text, state: state())
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

        // Non-speller, non-punct key with an active buffer: let the system handle it.
        return .passthrough
    }

    public func selectCandidate(at index: Int) -> EngineResult {
        let pageStart = pageIndex * config.candidateCount
        let absolute = pageStart + index
        guard absolute < allCandidates.count else {
            return .update(state())
        }
        let chosen = allCandidates[absolute]

        // English mode: replace the last word in the buffer with the chosen
        // completion, keeping previous words. User continues building a phrase.
        if buffer.hasPrefix("'") {
            let parts = buffer.split(separator: " ", omittingEmptySubsequences: false)
            if parts.count > 1 {
                var newParts = Array(parts.dropLast())
                newParts.append(Substring(chosen.text))
                buffer = newParts.joined(separator: " ") + " "
            } else {
                buffer = "'" + chosen.text + " "
            }
            recompute()
            return .update(state())
        }

        reset()
        return .commit(chosen.text, state: state())
    }

    // MARK: - Internals

    private func handleSpecial(_ special: KeyEvent.Special) -> EngineResult {
        switch special {
        case .backspace:
            if buffer.isEmpty { return .passthrough }
            buffer.removeLast()
            if buffer.isEmpty {
                reset()
                return .update(state())
            }
            recompute()
            return .update(state())

        case .space:
            if buffer.isEmpty { return .passthrough }
            // English mode: space appends to buffer (building a phrase).
            // Enter commits the whole thing.
            if buffer.hasPrefix("'") {
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
            guard let first = topCandidate() else { return .passthrough }
            let text = first.text
            reset()
            return .commit(text, state: state())

        case .enter:
            if buffer.isEmpty { return .passthrough }
            // English mode: strip the leading `'` and commit the phrase.
            // Normal mode: commit the raw buffer.
            var out = buffer
            if out.hasPrefix("'") { out = String(out.dropFirst()) }
            out = out.trimmingCharacters(in: .whitespaces)
            reset()
            return .commit(out, state: state())

        case .escape:
            if buffer.isEmpty { return .passthrough }
            reset()
            return .update(state())

        case .pageDown, .arrowDown:
            if !allCandidates.isEmpty, (pageIndex + 1) * config.candidateCount < allCandidates.count {
                pageIndex += 1
                return .update(state())
            }
            // At boundary: consume the key (don't let it leak as text)
            // but keep showing the current state.
            if !buffer.isEmpty { return .update(state()) }
            return .passthrough

        case .pageUp, .arrowUp:
            if pageIndex > 0 {
                pageIndex -= 1
                return .update(state())
            }
            if !buffer.isEmpty { return .update(state()) }
            return .passthrough

        default:
            return .passthrough
        }
    }

    private func recompute() {
        pageIndex = 0
        allCandidates = query(buffer)
    }

    private func query(_ input: String) -> [DisplayCandidate] {
        guard !input.isEmpty else { return [] }

        // Prefix dispatch.
        let first = input.first!
        if first == "'" && config.enableTempEnglish, let eng = resources.english {
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
            out.append(DisplayCandidate(text: e.text, annotation: e.code, source: .main))
        }
        // Insert emoji suggestions right after the first matching candidate so
        // they land on page 1 rather than trailing the full result set.
        if config.enableEmoji, let first = out.first {
            let emojis = resources.emoji.emojis(for: first.text)
            if !emojis.isEmpty {
                var insertAt = 1
                for emoji in emojis {
                    out.insert(
                        DisplayCandidate(text: emoji, annotation: first.text, source: .emoji),
                        at: insertAt
                    )
                    insertAt += 1
                }
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
            // Strip leading `i` from the annotation for display (xform/^i(.*)/$1/).
            let shown = e.code.hasPrefix("i") ? String(e.code.dropFirst()) : e.code
            out.append(DisplayCandidate(text: e.text, annotation: shown, source: .pinyin))
        }
        return out
    }

    private func queryEnglish(_ input: String, dict: CodeTable) -> [DisplayCandidate] {
        guard !input.isEmpty else { return [] }
        // For multi-word input ("hello world"), only complete the LAST word.
        let lastWord = input.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? input
        guard !lastWord.isEmpty else { return [] }
        let hits = dict.lookup(prefix: lastWord, limit: 32)
        return hits.map { DisplayCandidate(text: $0.text, annotation: "", source: .english) }
    }

    private func topCandidate() -> DisplayCandidate? { allCandidates.first }
    private func topCandidateText() -> String? { allCandidates.first?.text }

    private func isSpellerChar(_ c: Character) -> Bool {
        // Alphabet per cqlb schema: a-z plus ;,./
        if let s = c.asciiValue {
            if s >= UInt8(ascii: "a") && s <= UInt8(ascii: "z") { return true }
            if c == "'" || c == ";" || c == "," || c == "." || c == "/" { return true }
        }
        return false
    }

    private func isOverlapPunct(_ c: Character) -> Bool {
        return c == "," || c == "." || c == "/" || c == ";"
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
            highlightedIndex: 0,
            pageIndex: page,
            hasPrevPage: page > 0,
            hasNextPage: end < allCandidates.count,
            isPinyinMode: isInPinyinMode()
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

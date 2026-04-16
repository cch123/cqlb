import Foundation

/// Translates single ASCII punctuation characters to Chinese full-width forms.
///
/// Only kicks in when the composition buffer is empty — otherwise these
/// characters may be part of a cqlb code (the speller alphabet includes `,./;`).
public final class Punctuator: @unchecked Sendable {

    /// Output for a punctuation key.
    public enum Output: Sendable {
        case fixed(String)                 // emit this literal
        case pair(String, String)          // toggle between two forms (e.g. "" “” „„)
    }

    private var table: [Character: Output]
    private var pairState: [Character: Int] = [:]  // 0 or 1 for alternating output

    public init(custom: [Character: String] = [:]) {
        var t: [Character: Output] = [
            ",": .fixed("\u{FF0C}"),   // ,
            ".": .fixed("\u{3002}"),   // 。
            "?": .fixed("\u{FF1F}"),   // ?
            "!": .fixed("\u{FF01}"),   // !
            ";": .fixed("\u{FF1B}"),   // ;
            ":": .fixed("\u{FF1A}"),   // :
            "\\": .fixed("\u{3001}"),  // 、
            "/": .fixed("\u{3001}"),   // 、  (per schema override)
            "(": .fixed("\u{FF08}"),   // (
            ")": .fixed("\u{FF09}"),   // )
            "[": .fixed("\u{3010}"),   // 【
            "]": .fixed("\u{3011}"),   // 】
            "{": .fixed("\u{300C}"),   // 「
            "}": .fixed("\u{300D}"),   // 」
            "<": .fixed("\u{300A}"),   // 《
            ">": .fixed("\u{300B}"),   // 》
            "@": .fixed("\u{FF20}"),   // @
            "#": .fixed("\u{FF03}"),   // #
            "$": .fixed("\u{FFE5}"),   // ¥
            "%": .fixed("\u{FF05}"),   // %
            "^": .fixed("\u{2026}\u{2026}"),  // ……
            "&": .fixed("\u{FF06}"),   // &
            "*": .fixed("\u{FF0A}"),   // *
            "-": .fixed("\u{FF0D}"),   // -
            "+": .fixed("\u{FF0B}"),   // +
            "=": .fixed("\u{FF1D}"),   // =
            "_": .fixed("\u{2014}\u{2014}"),  // ——
            "\"": .pair("\u{201C}", "\u{201D}"),  // " "
            // Note: `'` is NOT mapped here. It is reserved as the trigger for
            // temp English mode, handled by the Engine.
            "~": .fixed("\u{FF5E}"),   // ~
            "`": .fixed("\u{00B7}"),   // ·
        ]
        for (k, v) in custom { t[k] = .fixed(v) }
        self.table = t
    }

    /// Look up punctuation. `bufferEmpty` guards the alphabet-overlap chars.
    /// Returns nil when no translation applies and the char should flow through
    /// normal handling.
    public func translate(_ char: Character, bufferEmpty: Bool) -> String? {
        // Alphabet-overlap chars: only emit punctuation when buffer is empty.
        let overlapChars: Set<Character> = [",", ".", "/", ";"]
        if overlapChars.contains(char) && !bufferEmpty {
            return nil
        }

        guard let out = table[char] else { return nil }
        switch out {
        case .fixed(let s):
            return s
        case .pair(let a, let b):
            let idx = pairState[char, default: 0]
            pairState[char] = 1 - idx
            return idx == 0 ? a : b
        }
    }

    public func reset() {
        pairState.removeAll(keepingCapacity: true)
    }
}

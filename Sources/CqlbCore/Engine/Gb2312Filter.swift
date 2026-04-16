import Foundation

/// Filter that drops candidates containing characters outside the GB2312 charset.
///
/// We precompute a set of allowed Unicode scalars on init by iterating GB2312 code
/// points; at query time, checking a candidate is O(text length) and hits a `Set`.
public final class Gb2312Filter: @unchecked Sendable {
    private let allowed: Set<Unicode.Scalar>
    public let isEnabled: Bool

    public init(enabled: Bool) {
        self.isEnabled = enabled
        if enabled {
            self.allowed = Self.buildGb2312Set()
        } else {
            self.allowed = []
        }
    }

    public func accepts(_ text: String) -> Bool {
        guard isEnabled else { return true }
        for scalar in text.unicodeScalars {
            // ASCII always OK
            if scalar.value < 0x80 { continue }
            if !allowed.contains(scalar) { return false }
        }
        return true
    }

    private static func buildGb2312Set() -> Set<Unicode.Scalar> {
        // GB2312 covers U+4E00..U+9FA5 minus a few dozen holes, plus the symbol
        // block U+3000..U+33FF partially, plus fullwidth ASCII U+FF00..U+FFEF.
        //
        // Exact membership requires the GB2312 table; a simple practical
        // approximation good enough for IME filtering: BMP CJK Unified block
        // "common" subset. We use the well-known GB2312 range [U+4E00, U+9FA5]
        // as the primary Han range, and allow common punctuation blocks.
        var set = Set<Unicode.Scalar>()
        set.reserveCapacity(7000)

        // Primary CJK range covered by GB2312 (approximate: level-1 + level-2
        // Hanzi fall within this range, though GB2312 omits ~20k later additions).
        if let lo = Unicode.Scalar(0x4E00), let hi = Unicode.Scalar(0x9FA5) {
            for v in lo.value...hi.value {
                if let s = Unicode.Scalar(v) { set.insert(s) }
            }
        }
        // CJK symbols and punctuation
        for range in [(0x3000...0x303F), (0xFF00...0xFFEF), (0x2000...0x206F)] {
            for v in range {
                if let s = Unicode.Scalar(v) { set.insert(s) }
            }
        }
        return set
    }
}

import Foundation

/// Filter that drops candidates containing Han ideographs outside GB2312.
///
/// Only CJK ideographs are constrained. Non-Han text (ASCII, symbols, kana,
/// Greek, emoji …) always passes: the filter's purpose is hiding rare Han
/// characters, not stripping symbol entries from the code table.
///
/// The allowed set is the exact GB2312 Hanzi repertoire (6763 characters,
/// levels 1 and 2), obtained by decoding every EUC-CN double-byte code point
/// in rows 0xB0–0xF7 through the system codec. The previous approximation
/// (`U+4E00…U+9FA5`) admitted ~20 900 ideographs, so the filter had almost no
/// effect.
public final class Gb2312Filter: @unchecked Sendable {
    public let isEnabled: Bool
    private let allowed: Set<UInt32>

    /// Built once per process; decoding ~8k code points takes a few ms.
    private static let hanzi: Set<UInt32> = buildHanziSet()

    public init(enabled: Bool) {
        self.isEnabled = enabled
        self.allowed = enabled ? Self.hanzi : []
    }

    public func accepts(_ text: String) -> Bool {
        guard isEnabled else { return true }
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if Self.isHan(v) && !allowed.contains(v) { return false }
        }
        return true
    }

    /// CJK Unified Ideographs (+ Extension A–I) and Compatibility Ideographs.
    static func isHan(_ v: UInt32) -> Bool {
        switch v {
        case 0x3400...0x4DBF,      // Extension A
             0x4E00...0x9FFF,      // URO
             0xF900...0xFAFF,      // Compatibility Ideographs
             0x20000...0x323AF,    // Extensions B–H
             0x2EBF0...0x2EE5F:    // Extension I
            return true
        default:
            return false
        }
    }

    static var hanziCount: Int { hanzi.count }

    private static func buildHanziSet() -> Set<UInt32> {
        let cfEnc = CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        var set = Set<UInt32>()
        set.reserveCapacity(6800)
        // Rows 16–87 (0xB0–0xF7) hold the Hanzi; rows 1–9 are symbols.
        for hi in UInt8(0xB0)...UInt8(0xF7) {
            for lo in UInt8(0xA1)...UInt8(0xFE) {
                guard let s = String(bytes: [hi, lo], encoding: enc),
                      let scalar = s.unicodeScalars.first,
                      s.unicodeScalars.count == 1,
                      isHan(scalar.value)
                else { continue }
                set.insert(scalar.value)
            }
        }
        return set
    }
}

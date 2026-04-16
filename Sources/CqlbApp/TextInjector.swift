import AppKit

/// Posts synthetic keystrokes to the focused application.
///
/// We use `keyboardSetUnicodeString` with virtual key 0, which tells the HID
/// layer "deliver this string as a single key event". Most Cocoa and web-based
/// text fields receive it as a multi-character insertion, matching the effect
/// of selecting a candidate in a real IME.
enum TextInjector {

    /// Magic value stamped on events we post, so our own event tap can
    /// recognise them and pass them through without re-processing.
    static let selfPostedMarker: Int64 = 0x43514C42  // 'CQLB'

    static func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let utf16 = Array(text.utf16)
        let chunkSize = 16
        var index = 0
        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            let slice = Array(utf16[index..<end])
            postChunk(slice)
            index = end
        }
    }

    private static func postChunk(_ utf16: [UniChar]) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        utf16.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
        }

        // Tag both events with our marker so EventTap can identify and skip
        // them — otherwise we'd re-enter the engine with our own output.
        down.setIntegerValueField(.eventSourceUserData, value: selfPostedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: selfPostedMarker)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

import AppKit
import InputMethodKit
import QuartzCore
import CqlbCore

/// The per-client controller instantiated by IMKServer. One instance exists
/// per connected text client, but they all share a single `EngineHost.shared`
/// engine (per plan decision — matches the CqlbApp model).
///
/// Responsibilities:
///  - Translate NSEvents → engine `KeyEvent`
///  - Drive inline preedit (`setMarkedText`) and final commits (`insertText`)
///  - Toggle Chinese/English mode (Option+Space, Shift quick-tap)
///  - Position the candidate window using the client's own rect
@objc(CqlbInputController)
final class CqlbInputController: IMKInputController {

    // MARK: - Per-controller state

    /// Shift quick-tap detection. A press + release within `shiftTapThreshold`
    /// with no other keystroke in between toggles Chinese/English.
    private var shiftDownTime: TimeInterval = 0
    private var shiftWasUsedAsModifier = false
    private let shiftTapThreshold: TimeInterval = 0.3

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // Fresh composition state per client activation. Config may have
        // changed via Settings since we last looked.
        EngineHost.shared.forceReloadConfig()
        EngineHost.shared.engine.reset()
        Log.imk.log("activateServer")
    }

    override func deactivateServer(_ sender: Any!) {
        // If the user types `ao` in app A then switches to app B, we must
        // commit or abandon the pending composition. Behavior matches
        // CqlbApp: commit the top candidate if one exists, else drop.
        let engine = EngineHost.shared.engine
        let state = engine.currentState()
        if !state.preedit.isEmpty, let first = state.candidates.first {
            commit(first.text, to: sender)
        } else if !state.preedit.isEmpty {
            // Nothing to commit; clear the inline marked text.
            if let client = sender as? IMKTextInput {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        engine.reset()
        CandidateWindowController.shared.hide()
        Log.imk.log("deactivateServer")
        super.deactivateServer(sender)
    }

    /// Called by the system when composition must end (e.g. mouse click
    /// elsewhere, app switch). Commit top candidate if any.
    override func commitComposition(_ sender: Any!) {
        let engine = EngineHost.shared.engine
        let state = engine.currentState()
        if !state.preedit.isEmpty, let first = state.candidates.first {
            commit(first.text, to: sender)
        }
        engine.reset()
        CandidateWindowController.shared.hide()
    }

    /// Event mask — we only care about keydown and flagsChanged.
    override func recognizedEvents(_ sender: Any!) -> Int {
        let mask = NSEvent.EventTypeMask.keyDown.rawValue
                 | NSEvent.EventTypeMask.flagsChanged.rawValue
        return Int(mask)
    }

    // MARK: - Event handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        Log.imk.log("handle type=\(event.type.rawValue) keyCode=0x\(String(event.keyCode, radix: 16)) flags=0x\(String(event.modifierFlags.rawValue, radix: 16))")

        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event, client: sender)
        case .keyDown:
            return handleKeyDown(event, client: sender)
        default:
            return false
        }
    }

    // MARK: - Flags (Shift quick-tap detection)

    private func handleFlagsChanged(_ event: NSEvent, client sender: Any!) -> Bool {
        // keyCode 0x38 = left Shift, 0x3C = right Shift
        let keyCode = event.keyCode
        guard keyCode == 0x38 || keyCode == 0x3C else { return false }

        let shiftOn = event.modifierFlags.contains(.shift)
        if shiftOn {
            shiftDownTime = CACurrentMediaTime()
            shiftWasUsedAsModifier = false
        } else {
            let elapsed = CACurrentMediaTime() - shiftDownTime
            if !shiftWasUsedAsModifier && elapsed < shiftTapThreshold && elapsed > 0.01 {
                toggleChineseEnglish(client: sender)
            }
        }
        // Always let the system see flag changes — we only observe.
        return false
    }

    // MARK: - Key down

    private func handleKeyDown(_ event: NSEvent, client sender: Any!) -> Bool {
        // Any keydown while Shift is held means Shift is acting as a
        // modifier, not a standalone tap.
        if event.modifierFlags.contains(.shift) {
            shiftWasUsedAsModifier = true
        }

        // Option+Space: toggle Chinese/English mode.
        // keyCode 49 = space.
        if event.keyCode == 49 && event.modifierFlags.contains(.option) {
            toggleChineseEnglish(client: sender)
            return true
        }

        // When in English mode, all keys pass through unchanged.
        if !ModeState.shared.chinese {
            Log.imk.log("keyDown: English mode, passthrough")
            return false
        }

        let key = Self.translate(event)
        Log.imk.log("keyDown: translated special=\(String(describing: key.special)) char=\(String(describing: key.char)) mods=\(key.modifiers.rawValue)")
        let engine = EngineHost.shared.engine
        let result = engine.processKey(key)

        switch result {
        case .passthrough:
            Log.imk.log("keyDown: result=passthrough")
            let s = engine.currentState()
            if s.preedit.isEmpty && s.candidates.isEmpty {
                CandidateWindowController.shared.hide()
                clearMarkedText(client: sender)
            }
            return false

        case .update(let state):
            Log.imk.log("keyDown: result=update highlighted=\(state.highlightedIndex) cands=\(state.candidates.count) preedit=\"\(state.preedit)\"")
            updateUI(state: state, client: sender)
            return true

        case .commit(let text, let state):
            Log.imk.log("keyDown: result=commit text=\"\(text)\"")
            commit(text, to: sender)
            updateUI(state: state, client: sender)
            return true
        }
    }

    // MARK: - Commit / preedit

    private func commit(_ text: String, to sender: Any!) {
        guard let client = sender as? IMKTextInput else {
            Log.imk.error("commit: client is not IMKTextInput")
            return
        }
        client.insertText(text,
                          replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func setMarkedText(_ text: String, client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        // Selection at end → visual caret at end of preedit.
        let sel = NSRange(location: (text as NSString).length, length: 0)
        client.setMarkedText(text,
                             selectionRange: sel,
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func clearMarkedText(client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        client.setMarkedText("",
                             selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Candidate window + inline preedit

    private func updateUI(state: EngineState, client sender: Any!) {
        // Inline preedit in the client (the big IMK win over CGEventTap).
        setMarkedText(state.preedit, client: sender)

        if state.candidates.isEmpty {
            if (state.isPinyinMode || state.isEnglishMode) && !state.preedit.isEmpty {
                let caret = clientCaretRect(sender, markedLength: (state.preedit as NSString).length)
                CandidateWindowController.shared.show(state: state, near: caret)
                return
            }
            CandidateWindowController.shared.hide()
            if !state.preedit.isEmpty {
                EngineHost.shared.engine.reset()
                clearMarkedText(client: sender)
            }
            return
        }

        let caret = clientCaretRect(sender, markedLength: (state.preedit as NSString).length)
        CandidateWindowController.shared.show(state: state, near: caret)
    }

    /// Ask the client for the screen-coordinate rect of the marked text's
    /// first character. Returns `.zero` if the client doesn't support this
    /// (some Carbon / Electron apps); the candidate window falls back to
    /// screen-center in that case.
    private func clientCaretRect(_ sender: Any!, markedLength: Int) -> NSRect {
        guard let client = sender as? IMKTextInput else { return .zero }
        let range = NSRange(location: 0, length: markedLength)
        var actual = NSRange(location: NSNotFound, length: 0)
        let rect = client.firstRect(forCharacterRange: range, actualRange: &actual)
        // Bogus values seen in practice: NaN width/height on misbehaving clients.
        if rect.size.width.isNaN || rect.size.height.isNaN { return .zero }
        return rect
    }

    // MARK: - Mode toggle

    private func toggleChineseEnglish(client sender: Any!) {
        // Before switching out of Chinese mode, commit any pending preedit
        // so the user's in-flight text isn't silently dropped.
        let engine = EngineHost.shared.engine
        if ModeState.shared.chinese {
            let state = engine.currentState()
            if !state.preedit.isEmpty, let first = state.candidates.first {
                commit(first.text, to: sender)
            } else {
                clearMarkedText(client: sender)
            }
            engine.reset()
            CandidateWindowController.shared.hide()
        }
        ModeState.shared.chinese.toggle()
        ModeIndicator.shared.show(chinese: ModeState.shared.chinese)
    }

    // MARK: - NSEvent → KeyEvent

    private static func translate(_ event: NSEvent) -> KeyEvent {
        let keyCode = event.keyCode
        let special: KeyEvent.Special?
        switch keyCode {
        case 0x33: special = .backspace
        case 0x24, 0x4C: special = .enter
        case 0x35: special = .escape
        case 0x31: special = .space
        case 0x30: special = .tab
        case 0x7B: special = .arrowLeft
        case 0x7C: special = .arrowRight
        case 0x7D: special = .arrowDown
        case 0x7E: special = .arrowUp
        case 0x74: special = .pageUp
        case 0x79: special = .pageDown
        default:   special = nil
        }

        let flags = event.modifierFlags
        var mods: KeyEvent.Modifiers = []
        if flags.contains(.shift)    { mods.insert(.shift) }
        if flags.contains(.control)  { mods.insert(.control) }
        if flags.contains(.option)   { mods.insert(.option) }
        if flags.contains(.command)  { mods.insert(.command) }

        if let s = special {
            return KeyEvent(char: nil, special: s, modifiers: mods)
        }

        // `event.characters` is the text the system would produce if the
        // event were passed through (respects shift/option/layout). That is
        // exactly what the engine expects.
        if let s = event.characters, let c = s.first {
            return KeyEvent(char: c, modifiers: mods)
        }
        return KeyEvent(char: nil, modifiers: mods)
    }
}

/// Process-wide Chinese/English toggle. Kept outside the controller because
/// all clients share this state — switching apps shouldn't reset it.
final class ModeState {
    static let shared = ModeState()
    /// true = Chinese (engine active), false = English (pass-through)
    var chinese: Bool = true
    private init() {}
}

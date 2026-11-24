import AppKit
import InputMethodKit
import QuartzCore
import CqlbCore
import CqlbSettingsUI

/// The per-client controller instantiated by IMKServer. One instance exists
/// per connected text client, but they all share a single `EngineHost.shared`
/// engine.
///
/// Responsibilities:
///  - Translate NSEvents → engine `KeyEvent`
///  - Drive inline preedit (`setMarkedText`) and final commits (`insertText`)
///  - Toggle Chinese/English mode (Option+Space, Shift quick-tap)
///  - Position the candidate window using the client's own rect
// No @objc(name) annotation: the class inherits from IMKInputController
// (an @objc class) so Swift auto-exposes it to the ObjC runtime under the
// module-qualified name `CqlbIME.CqlbInputController`. Info.plist's
// `InputMethodServerControllerClass` uses that exact string, matching the
// pattern Apple's IMK samples and Squirrel use.
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
        EngineHost.shared.reloadConfigIfChanged()
        EngineHost.shared.engine.reset()
        Log.imk.log("activateServer")
    }

    override func deactivateServer(_ sender: Any!) {
        // If the user types `ao` in app A then switches to app B, we must
        // commit or abandon the pending composition. Behavior matches
        // Commit the top candidate if one exists; otherwise drop the
        // unfinished code and clear marked text.
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

    // MARK: - IME menu (shown when user picks this IME in the menu-bar switcher)

    /// The system calls this when the user opens the IME's menu from the
    /// menu-bar input switcher. Settings are hosted in-process so the
    /// distributable IME bundle does not depend on a second app being
    /// installed beside it.
    override func menu() -> NSMenu! {
        // The system asks for the menu far more often than it shows it
        // (observed: once per keystroke), so build it once per controller
        // and keep this path free of logging and allocation.
        return cachedMenu
    }

    private lazy var cachedMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false

        func item(_ titleKey: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(
                title: NSLocalizedString(titleKey, comment: ""),
                action: action,
                keyEquivalent: ""
            )
            // macOS 26 may dispatch IMK menu items as ordinary AppKit
            // target/action instead of routing through
            // doCommand(by:command:). Keep the target explicit, while
            // doCommand below covers the classic IMK command path.
            item.target = self
            item.isEnabled = true
            return item
        }

        menu.addItem(item("Settings...", #selector(openSettingsMenuItem)))
        menu.addItem(item("Edit User Dictionary...", #selector(openUserDictMenuItem)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("About cqlb", #selector(openAboutMenuItem)))
        return menu
    }()

    /// IMK menu commands are not normal AppKit target/action dispatch. The
    /// system calls this method with the menu item's selector, and older IMK
    /// default dispatch can silently miss Swift actor-isolated actions. Route
    /// commands explicitly so Settings keeps working when invoked from the
    /// menu-bar input switcher.
    override func doCommand(by selector: Selector!, command info: [AnyHashable : Any]!) {
        guard let selector else { return }
        Log.imk.log("menu command \(NSStringFromSelector(selector))")

        if selector == #selector(openSettingsMenuItem) || selector == #selector(openSettings(_:)) {
            openSettings(info)
        } else if selector == #selector(openAboutMenuItem) || selector == #selector(openAbout(_:)) {
            openAbout(info)
        } else if selector == #selector(openUserDictMenuItem) {
            openUserDictMenuItem()
        } else {
            super.doCommand(by: selector, command: info)
        }
    }

    @objc
    func openSettingsMenuItem() {
        openSettings(nil)
    }

    @objc(openSettings:)
    func openSettings(_ sender: Any?) {
        Log.imk.log("open settings requested")
        // Menu commands arrive while TextInputMenuAgent is still tracking the
        // status-item menu. Presenting immediately can create the window while
        // the menu is tearing down, leaving it ordered behind the active text
        // client. Defer one run-loop turn so the settings window can become
        // key reliably.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Log.imk.log("present settings window")
            SettingsWindowPresenter.shared.show {
                EngineHost.shared.forceReloadConfig()
            }
        }
    }

    @objc
    func openUserDictMenuItem() {
        Log.imk.log("open user dictionary requested")
        DispatchQueue.main.async {
            UserDict.createTemplateIfMissing()
            // Open as plain text regardless of the .yaml handler; edits are
            // picked up by EngineHost's directory watcher on save.
            let config = NSWorkspace.OpenConfiguration()
            let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            NSWorkspace.shared.open([UserDict.url], withApplicationAt: textEdit, configuration: config)
        }
    }

    @objc
    func openAboutMenuItem() {
        openAbout(nil)
    }

    @objc(openAbout:)
    func openAbout(_ sender: Any?) {
        Log.imk.log("open about requested")
        DispatchQueue.main.async {
            if let url = URL(string: "https://github.com/cch123/cqlb") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Event handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

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
        guard keyCode == 0x38 || keyCode == 0x3C else {
            // Another modifier changed while Shift is down (e.g. Shift+Cmd):
            // Shift is a modifier, not a tap.
            if shiftDownTime > 0 { shiftWasUsedAsModifier = true }
            return false
        }
        let tapSetting = EngineHost.shared.currentConfig.shortcuts.shiftTap
        let keyEnabled: Bool
        switch tapSetting {
        case .both:  keyEnabled = true
        case .left:  keyEnabled = keyCode == 0x38
        case .right: keyEnabled = keyCode == 0x3C
        case .none:  keyEnabled = false
        }
        guard keyEnabled else { return false }

        let shiftOn = event.modifierFlags.contains(.shift)
        if shiftOn {
            shiftDownTime = CACurrentMediaTime()
            shiftWasUsedAsModifier = false
        } else {
            let elapsed = CACurrentMediaTime() - shiftDownTime
            // Clear the down-time as soon as we see the release — prevents
            // a second flagsChanged event (e.g. IMK synthesizes one while
            // the system also delivers one) from re-triggering the toggle
            // and making it look like Shift was tapped twice.
            shiftDownTime = 0
            // Shift+click (extend selection) produces no keyDown, so the
            // keyDown-based check above misses it. Ask the window server
            // whether a mouse button went down while Shift was held.
            let sinceClick = min(
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
            )
            if sinceClick < elapsed { shiftWasUsedAsModifier = true }
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
        // modifier, not a single-key tap.
        if event.modifierFlags.contains(.shift) {
            shiftWasUsedAsModifier = true
        }

        if isToggleChord(event) {
            toggleChineseEnglish(client: sender)
            return true
        }

        // When in English mode, all keys pass through unchanged.
        if !ModeState.shared.chinese {
            return false
        }

        let key = Self.translate(event)
        let engine = EngineHost.shared.engine
        let result = engine.processKey(key)

        switch result {
        case .passthrough:
            let s = engine.currentState()
            if s.preedit.isEmpty && s.candidates.isEmpty {
                CandidateWindowController.shared.hide()
                clearMarkedText(client: sender)
            }
            return false

        case .update(let state):
            updateUI(state: state, client: sender)
            return true

        case .commit(let text, let state):
            commit(text, to: sender)
            updateUI(state: state, client: sender)
            return true
        }
    }

    /// Chinese/English toggle chord per `shortcuts.toggleChineseEnglish`.
    /// The chord must be exact: Option+Cmd+Space etc. are left to the system.
    private func isToggleChord(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }  // space
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch EngineHost.shared.currentConfig.shortcuts.toggleChineseEnglish {
        case .optionSpace: return mods == .option
        case .shiftSpace:  return mods == .shift
        case .none:        return false
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
        // Inline preedit in the client keeps the composing code inside the
        // active text field instead of drawing it only in our candidate UI.
        setMarkedText(state.preedit, client: sender)

        // Mouse selection. The handler resolves the client at click time via
        // `client()` rather than capturing `sender`.
        let onSelect: (Int) -> Void = { [weak self] index in
            self?.candidateClicked(index)
        }

        if state.candidates.isEmpty {
            if state.keepsPreeditWithoutCandidates && !state.preedit.isEmpty {
                let caret = clientCaretRect(sender, markedLength: (state.preedit as NSString).length)
                CandidateWindowController.shared.show(state: state, near: caret, onSelect: onSelect)
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
        CandidateWindowController.shared.show(state: state, near: caret, onSelect: onSelect)
    }

    /// A candidate was clicked in the candidate window.
    private func candidateClicked(_ index: Int) {
        guard let client = self.client() else { return }
        switch EngineHost.shared.engine.selectCandidate(at: index) {
        case .commit(let text, let state):
            commit(text, to: client)
            updateUI(state: state, client: client)
        case .update(let state):
            updateUI(state: state, client: client)
        case .passthrough:
            break
        }
    }

    /// Ask the client for the screen-coordinate rect of the marked text's
    /// insertion point. Tries two IMK APIs in order:
    ///
    /// 1. `attributes(forCharacterIndex:lineHeightRectangle:)` — preferred
    ///    by Apple's sample code; returns a rect describing the full line
    ///    height at the caret. Most apps (TextEdit, Safari, Chrome, etc.)
    ///    implement this correctly.
    /// 2. `firstRect(forCharacterRange:actualRange:)` — older NSTextInput
    ///    API; more widely supported but returns zero rect on some apps
    ///    when the range is entirely inside marked text.
    ///
    /// Returns `.zero` if both fail (rare — usually Terminal or Carbon
    /// apps). The candidate window falls back to screen-center in that
    /// case.
    private func clientCaretRect(_ sender: Any!, markedLength: Int) -> NSRect {
        guard let client = sender as? IMKTextInput else { return .zero }

        // Attempt 1: attributes(forCharacterIndex:lineHeightRectangle:).
        // The index is 0 because IMK marked text is always at index 0 of
        // the composition range from the client's perspective.
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        if isUsable(lineRect) {
            return lineRect
        }

        // Attempt 2: firstRect(forCharacterRange:actualRange:). For marked
        // text, use a 1-character range because some clients return zero for
        // zero-length marked ranges. With no marked text, a zero-length range
        // asks for the insertion caret itself, which is what mode switching
        // needs.
        let probeLen = markedLength > 0 ? max(1, markedLength) : 0
        let range = NSRange(location: 0, length: probeLen)
        var actual = NSRange(location: NSNotFound, length: 0)
        let firstRect = client.firstRect(forCharacterRange: range, actualRange: &actual)
        if isUsable(firstRect) {
            return firstRect
        }

        // Both APIs returned bogus — typical in Terminal and some Carbon
        // apps. CandidateWindow will fall back to screen-center.
        return .zero
    }

    /// A rect is "usable" as a caret position if it has non-NaN values and
    /// isn't pinned at the screen origin (which most apps use as "I don't
    /// know" sentinel).
    private func isUsable(_ rect: NSRect) -> Bool {
        if rect.size.width.isNaN || rect.size.height.isNaN { return false }
        if rect.origin.x.isNaN || rect.origin.y.isNaN { return false }
        if rect.origin.x == 0 && rect.origin.y == 0 { return false }
        return true
    }

    // MARK: - Mode toggle

    private func toggleChineseEnglish(client sender: Any!) {
        // Before switching out of Chinese mode, commit any pending preedit
        // so the user's in-flight text isn't silently dropped.
        let engine = EngineHost.shared.engine
        let stateBeforeToggle = engine.currentState()
        let caret = clientCaretRect(
            sender,
            markedLength: (stateBeforeToggle.preedit as NSString).length
        )
        if ModeState.shared.chinese {
            if !stateBeforeToggle.preedit.isEmpty, let first = stateBeforeToggle.candidates.first {
                commit(first.text, to: sender)
            } else {
                clearMarkedText(client: sender)
            }
            engine.reset()
            CandidateWindowController.shared.hide()
        }
        ModeState.shared.chinese.toggle()
        ModeIndicator.shared.show(chinese: ModeState.shared.chinese, near: caret)
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
            // Function keys (F1…, Home, End, forward delete …) arrive as
            // private-use scalars U+F700–U+F8FF. They carry no text.
            if let scalar = c.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) {
                return KeyEvent(char: nil, modifiers: mods)
            }
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

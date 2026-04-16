import AppKit
import QuartzCore
import CqlbCore

/// Global keyboard event interceptor. Runs on the main run loop, owns the
/// activation state (cqlb on/off via Caps Lock toggle) and drives the Engine.
///
/// Design:
/// - We listen for `.keyDown` and `.flagsChanged` on `cgSessionEventTap`.
/// - Caps Lock flipping ON enters cqlb mode: keydowns are consumed and fed to
///   the engine. The candidate window appears near the caret.
/// - Caps Lock flipping OFF exits cqlb mode: any pending preedit is committed
///   (top candidate) and the tap returns to passthrough.
/// - While active, engine `.commit` results trigger `TextInjector.inject`.
final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var active: Bool = false {
        didSet { activeDidChange(from: oldValue) }
    }
    /// Cached caret position. Only refreshed on activation or after a commit.
    private var cachedCaretRect: NSRect = .zero
    /// Debounce timer for candidate window display.
    private var displayTimer: Timer?
    private let displayDelay: TimeInterval = 0.03

    /// Shift-tap detection: track when Shift went down and whether any other
    /// key was pressed while it was held. A quick tap (<300ms) with no
    /// intervening keys toggles Chinese/English mode.
    private var shiftDownTime: TimeInterval = 0
    private var shiftWasUsedAsModifier = false
    private let shiftTapThreshold: TimeInterval = 0.3

    init() {}

    func start() throws {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            throw NSError(
                domain: "cqlb",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "failed to create event tap; check Accessibility permission"]
            )
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.runLoopSource = source
        Log.tap.log("event tap running")
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Events we ourselves posted via TextInjector carry a magic marker.
        // Pass them straight through so we don't re-process our own output.
        if event.getIntegerValueField(.eventSourceUserData) == TextInjector.selfPostedMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            return handleFlagsChanged(event)
        }
        if type == .keyDown {
            return handleKeyDown(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let shiftOn = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Shift key codes: left=0x38, right=0x3C
        if keyCode == 0x38 || keyCode == 0x3C {
            if shiftOn {
                // Shift pressed down — start tracking.
                shiftDownTime = CACurrentMediaTime()
                shiftWasUsedAsModifier = false
            } else {
                // Shift released — if it was a quick tap with no keys in
                // between, toggle mode.
                let elapsed = CACurrentMediaTime() - shiftDownTime
                if !shiftWasUsedAsModifier && elapsed < shiftTapThreshold && elapsed > 0.01 {
                    active.toggle()
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Any keydown while Shift is held means Shift is being used as a
        // modifier (e.g. Shift+A), not as a standalone tap.
        if event.flags.contains(.maskShift) {
            shiftWasUsedAsModifier = true
        }

        // Activation hotkey: Option+Space toggles cqlb mode.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if keyCode == 0x31 /* Space */ && flags.contains(.maskAlternate) {
            active.toggle()
            return nil
        }

        guard active else {
            return Unmanaged.passUnretained(event)
        }

        let key = Self.translate(event)
        let engine = EngineHost.shared.engine
        let result = engine.processKey(key)

        switch result {
        case .passthrough:
            let s = engine.currentState()
            if s.preedit.isEmpty && s.candidates.isEmpty {
                CandidateWindowController.shared.hide()
            }
            return Unmanaged.passUnretained(event)

        case .update(let state):
            updateUI(state: state)
            return nil

        case .commit(let text, let state):
            updateUI(state: state)
            DispatchQueue.main.async { [weak self] in
                TextInjector.inject(text)
                self?.cachedCaretRect = CaretLocator.currentCaretRect()
            }
            return nil
        }
    }

    // MARK: - State transitions

    private func activeDidChange(from old: Bool) {
        if active {
            EngineHost.shared.forceReloadConfig()
            EngineHost.shared.engine.reset()
            cachedCaretRect = CaretLocator.currentCaretRect()
            ModeIndicator.shared.show(chinese: true)
        } else {
            let engine = EngineHost.shared.engine
            let state = engine.currentState()
            if !state.preedit.isEmpty, let first = state.candidates.first {
                TextInjector.inject(first.text)
            }
            engine.reset()
            CandidateWindowController.shared.hide()
            ModeIndicator.shared.show(chinese: false)
        }
    }

    // MARK: - Helpers

    private func updateUI(state: EngineState) {
        if state.candidates.isEmpty {
            if state.isPinyinMode && !state.preedit.isEmpty {
                // Pinyin mode: keep window visible so user can backspace.
                CandidateWindowController.shared.show(state: state, near: cachedCaretRect)
                return
            }
            // Main mode or empty buffer: hide and clear.
            displayTimer?.invalidate()
            displayTimer = nil
            CandidateWindowController.shared.hide()
            if !state.preedit.isEmpty {
                // Main mode had no candidates — clear the engine buffer.
                EngineHost.shared.engine.reset()
            }
            return
        }
        // If the window is ALREADY visible, update content immediately (cheap:
        // just a redraw). Only debounce the INITIAL show (orderFrontRegardless
        // is the expensive part).
        if CandidateWindowController.shared.visible {
            CandidateWindowController.shared.show(state: state, near: cachedCaretRect)
            return
        }
        // Window not yet visible: debounce. If another keystroke arrives
        // within 30ms, this timer is cancelled and replaced. Fast 4-char
        // auto-select sequences never trigger a window show at all.
        displayTimer?.invalidate()
        let caret = cachedCaretRect
        displayTimer = Timer.scheduledTimer(withTimeInterval: displayDelay, repeats: false) { [weak self] _ in
            guard self != nil else { return }
            CandidateWindowController.shared.show(state: state, near: caret)
        }
    }

    private static func translate(_ event: CGEvent) -> KeyEvent {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
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

        let flags = event.flags
        var mods: KeyEvent.Modifiers = []
        if flags.contains(.maskShift)     { mods.insert(.shift) }
        if flags.contains(.maskControl)   { mods.insert(.control) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskCommand)   { mods.insert(.command) }

        if let s = special {
            return KeyEvent(char: nil, special: s, modifiers: mods)
        }

        // Extract the character produced by this event.
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        if length > 0 {
            let s = String(utf16CodeUnits: chars, count: length)
            if var c = s.first {
                // We repurpose Caps Lock as our activation toggle. While
                // active, the hardware caps-lock LED is on and the system
                // would normally deliver ASCII letters in uppercase. Undo
                // that here so the engine sees lowercase codes (`a-z`).
                if let ascii = c.asciiValue,
                   ascii >= UInt8(ascii: "A") && ascii <= UInt8(ascii: "Z")
                {
                    c = Character(UnicodeScalar(ascii + 32))
                }
                return KeyEvent(char: c, modifiers: mods)
            }
        }
        return KeyEvent(char: nil, modifiers: mods)
    }
}

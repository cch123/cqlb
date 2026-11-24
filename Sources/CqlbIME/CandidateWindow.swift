import AppKit
import CqlbCore

/// Non-activating floating panel that displays the engine's candidate list.
///
/// View stack, back to front:
///
///     PanelBackground   Liquid Glass (macOS 26+) or a masked visual-effect view
///     HighlightView     accent-gradient pill behind the highlighted candidate;
///                       a separate layer so it can slide between candidates
///     CandidateView     draws all text; transparent background
///
/// Positioning: the caret rect is provided by the IMK input controller, which
/// asks the client directly. When the client returns a zero rect (Terminal,
/// some Carbon apps), the panel falls back to a fixed spot near the bottom of
/// the screen.
final class CandidateWindowController {
    static let shared = CandidateWindowController()

    private let window: NSPanel
    private let background: PanelBackground
    private let highlight = HighlightView()
    private let view: CandidateView
    private(set) var visible = false
    /// Identity of the candidate page last shown; the highlight only slides
    /// when the page is unchanged and just the highlighted index moved.
    private var lastPageKey = ""

    private init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 400, height: 60)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Hidden state is alpha 0, not ordered out: ignore the mouse until
        // `show` makes the panel visible (it re-enables events for
        // click-to-select).
        panel.ignoresMouseEvents = true

        let background = PanelBackground(frame: initialFrame)
        let content = CandidateView(frame: background.content.bounds)
        content.autoresizingMask = [.width, .height]
        background.content.addSubview(highlight)
        background.content.addSubview(content)

        panel.contentView = background
        self.window = panel
        self.background = background
        self.view = content
    }

    /// Show or update the candidate window.
    ///
    /// - Parameters:
    ///   - caretRect: screen-coordinate rect of the client's text caret
    ///     (bottom-left origin). `.zero` falls back to a fixed position.
    ///   - appearance: defaults to the live config; injectable for the
    ///     `--preview-candidates` development mode.
    func show(
        state: EngineState,
        near caretRect: NSRect,
        appearance: Config.Appearance = EngineHost.shared.currentConfig.appearance,
        onSelect: ((Int) -> Void)? = nil
    ) {
        view.onSelect = onSelect
        window.ignoresMouseEvents = false
        applyColorScheme(appearance.colorScheme)
        view.update(state: state, appearance: appearance)

        let layout = view.layout
        let size = layout.size
        let hasCaret = !(caretRect.size == .zero || (caretRect.origin.x == 0 && caretRect.origin.y == 0))
        // Use the screen that contains the caret, not `NSScreen.main` (the
        // screen with the key window), so the panel follows the text field on
        // multi-display setups.
        let caretPoint = NSPoint(x: caretRect.midX, y: caretRect.midY)
        let screen = (hasCaret ? NSScreen.screens.first { $0.frame.contains(caretPoint) } : nil)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let gap: CGFloat = 6
        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height - gap)
        if !hasCaret {
            origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.minY + 200
            )
        }
        if origin.x + size.width > screenFrame.maxX { origin.x = screenFrame.maxX - size.width - 8 }
        if origin.x < screenFrame.minX { origin.x = screenFrame.minX + 8 }
        if origin.y < screenFrame.minY {
            // Not enough room below the caret (text field near the bottom of
            // the screen): flip above the line instead of clamping, which
            // would cover the text being typed.
            origin.y = hasCaret ? caretRect.maxY + gap : screenFrame.minY + 8
        }
        if origin.y + size.height > screenFrame.maxY { origin.y = screenFrame.maxY - size.height }

        let newFrame = NSRect(origin: origin, size: size)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
        let accent = appearance.accentColor.nsColor
        background.configure(
            cornerRadius: layout.panelRadius,
            accent: accent,
            glow: appearance.glow,
            appearance: window.effectiveAppearance
        )
        view.needsDisplay = true

        // Highlight pill: slide when only the highlighted index changed on
        // an otherwise identical page; snap in every other case (typing must
        // never wait on an animation).
        let pageKey = "\(state.pageIndex)|" + state.candidates.map(\.text).joined(separator: "\u{1F}")
        let slide = visible && pageKey == lastPageKey
        lastPageKey = pageKey
        highlight.set(
            frame: layout.highlightRect,
            cornerRadius: layout.itemRadius,
            accent: accent,
            glow: appearance.glow,
            appearance: window.effectiveAppearance,
            animated: slide
        )

        if !visible {
            visible = true
            background.setAnimating(true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.09
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard visible else { return }
        window.alphaValue = 0
        // Alpha 0 alone leaves the window in place; stop it from taking
        // clicks aimed at the text underneath while hidden.
        window.ignoresMouseEvents = true
        view.onSelect = nil
        visible = false
        lastPageKey = ""
        // No repeating animation while the panel is invisible.
        background.setAnimating(false)
    }

    private func applyColorScheme(_ scheme: Config.Appearance.ColorScheme) {
        switch scheme {
        case .system:
            // A floating panel without a parent window needs an explicit
            // appearance to pick up system dark mode — `nil` (inherit)
            // leaves it stuck on the first appearance it saw.
            window.appearance = NSApp.effectiveAppearance
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Background

/// Rounded translucent backing for the panel. `content` hosts the highlight
/// and the candidate view, in a flipped (top-left origin) coordinate space.
private final class PanelBackground: NSView {
    let content = FlippedView()
    private var effectView: NSVisualEffectView?
    private var glassView: NSView?
    private let border = FlowingBorderView()

    private var cornerRadius: CGFloat = 14
    private var maskedSize: NSSize = .zero
    private var maskedRadius: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.contentView = content
            addSubview(glass)
            glassView = glass
        } else {
            let vfx = NSVisualEffectView(frame: bounds)
            vfx.material = .menu
            vfx.blendingMode = .behindWindow
            vfx.state = .active
            vfx.autoresizingMask = [.width, .height]
            vfx.addSubview(content)
            addSubview(vfx)
            effectView = vfx
        }

        border.frame = bounds
        border.autoresizingMask = [.width, .height]
        addSubview(border)
        applyCornerRadius()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(cornerRadius: CGFloat, accent: NSColor, glow: Bool, appearance: NSAppearance) {
        self.cornerRadius = cornerRadius
        applyCornerRadius()
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            // A faint accent tint on the glass ties the panel to the theme.
            glass.tintColor = glow ? accent.withAlphaComponent(0.10) : nil
        }
        border.configure(cornerRadius: cornerRadius, accent: accent, enabled: glow, appearance: appearance)
    }

    func setAnimating(_ animating: Bool) {
        border.setAnimating(animating)
    }

    override func layout() {
        super.layout()
        applyCornerRadius()
    }

    private func applyCornerRadius() {
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            return
        }
        guard let effectView, bounds.size != maskedSize || cornerRadius != maskedRadius else { return }
        maskedSize = bounds.size
        maskedRadius = cornerRadius
        let radius = cornerRadius
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        effectView.maskImage = image
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension NSColor {
    /// The same color with its hue rotated by `degrees`. Resolve dynamic
    /// system colors under the intended appearance before calling.
    func hueShifted(by degrees: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var shifted = (h + degrees / 360).truncatingRemainder(dividingBy: 1)
        if shifted < 0 { shifted += 1 }
        return NSColor(hue: shifted, saturation: s, brightness: b, alpha: a)
    }
}

// MARK: - Flowing border

/// A band of accent-colored light travelling around the panel's edge.
///
/// Structure: a conic gradient (mostly transparent, with two lit arcs)
/// rotates inside a layer whose mask is the panel's stroked outline, so only
/// the 1.5pt rim shows the moving light. The rotation runs only while the
/// panel is visible.
private final class FlowingBorderView: NSView {
    private let spinner = CAGradientLayer()
    private let outline = CAShapeLayer()
    private var radius: CGFloat = 14
    private var animating = false
    private var enabled = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        spinner.type = .conic
        spinner.startPoint = CGPoint(x: 0.5, y: 0.5)
        spinner.endPoint = CGPoint(x: 0.5, y: 0)
        spinner.locations = [0, 0.10, 0.18, 0.28, 0.42, 0.60, 0.72, 0.86, 1]
        outline.fillColor = nil
        outline.strokeColor = NSColor.black.cgColor
        outline.lineWidth = 1.5
        layer?.addSublayer(spinner)
        layer?.mask = outline
    }

    required init?(coder: NSCoder) { fatalError() }

    // Decorative only.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(cornerRadius: CGFloat, accent: NSColor, enabled: Bool, appearance: NSAppearance) {
        radius = cornerRadius
        self.enabled = enabled
        isHidden = !enabled
        appearance.performAsCurrentDrawingAppearance {
            let clear = accent.withAlphaComponent(0).cgColor
            let bright = (accent.blended(withFraction: 0.65, of: .white) ?? accent).cgColor
            spinner.colors = [
                clear,
                accent.cgColor,
                bright,
                accent.hueShifted(by: 45).cgColor,
                clear,
                clear,
                accent.hueShifted(by: -40).withAlphaComponent(0.8).cgColor,
                clear,
                clear,
            ]
        }
        needsLayout = true
        updateAnimation()
    }

    func setAnimating(_ animating: Bool) {
        self.animating = animating
        updateAnimation()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        outline.frame = b
        let inset = b.insetBy(dx: 0.75, dy: 0.75)
        // CGPath traps if the corner radius exceeds half the shorter side.
        let r = max(0, min(radius - 0.75, min(inset.width, inset.height) / 2 - 0.01))
        outline.path = CGPath(roundedRect: inset, cornerWidth: r, cornerHeight: r, transform: nil)
        // Square large enough to cover the panel at any rotation angle.
        let d = hypot(b.width, b.height)
        spinner.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        spinner.position = CGPoint(x: b.midX, y: b.midY)
        CATransaction.commit()
    }

    private func updateAnimation() {
        let key = "spin"
        if animating && enabled {
            guard spinner.animation(forKey: key) == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 4.5
            spin.repeatCount = .infinity
            spinner.add(spin, forKey: key)
        } else {
            spinner.removeAnimation(forKey: key)
        }
    }
}

// MARK: - Highlight

/// Gradient pill behind the highlighted candidate, with an optional glow.
///
/// The view's backing layer is unclipped and carries the glow (a layer
/// shadow, derived from the pill sublayer's shape); the gradient lives in a
/// clipped sublayer that tracks the view's bounds. Animating the view's
/// frame therefore slides and resizes pill and glow together.
private final class HighlightView: NSView {
    private let pill = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        pill.startPoint = CGPoint(x: 0, y: 0.5)
        pill.endPoint = CGPoint(x: 1, y: 0.5)
        pill.masksToBounds = true
        pill.cornerCurve = .continuous
        pill.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        pill.frame = bounds
        layer?.addSublayer(pill)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Purely decorative: clicks go to the candidate view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        pill.frame = bounds
    }

    func set(
        frame: NSRect,
        cornerRadius: CGFloat,
        accent: NSColor,
        glow: Bool,
        appearance: NSAppearance,
        animated: Bool
    ) {
        isHidden = frame.isEmpty
        guard !frame.isEmpty, let layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            if glow {
                // Two-hue sweep: accent into its neighbouring hue.
                pill.colors = [accent.cgColor, accent.hueShifted(by: 38).cgColor]
            } else {
                let light = (accent.blended(withFraction: 0.18, of: .white) ?? accent).cgColor
                pill.colors = [light, accent.cgColor]
            }
            layer.shadowColor = accent.cgColor
        }
        pill.cornerRadius = cornerRadius
        layer.shadowOpacity = glow ? 0.65 : 0
        layer.shadowRadius = 7
        layer.shadowOffset = .zero
        CATransaction.commit()

        if animated && self.frame != frame {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                self.animator().frame = frame
                self.pill.frame = CGRect(origin: .zero, size: frame.size)
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.frame = frame
            pill.frame = CGRect(origin: .zero, size: frame.size)
            CATransaction.commit()
        }
    }
}

// MARK: - Layout

/// Geometry of one candidate page. Computed once per update and used for
/// sizing, drawing and hit-testing alike, so the three can never disagree
/// (sizing used to re-implement the draw logic and drifted from it).
struct CandidateLayout {
    struct Item {
        var rect: NSRect = .zero          // hit area and highlight frame
        var index: String = ""
        var text: String = ""
        var hint: String = ""             // emphasized: keys still to type
        var note: String = ""             // secondary annotation
        var indexX: CGFloat = 0
        var textX: CGFloat = 0
        var hintX: CGFloat = 0
        var noteX: CGFloat = 0
    }

    var size: NSSize = .zero
    var items: [Item] = []
    var highlightRect: NSRect = .zero
    var panelRadius: CGFloat = 14
    var itemRadius: CGFloat = 9
    var rowHeight: CGFloat = 30
    /// Header row (mode chip + preedit); nil when hidden.
    var headerRect: NSRect?
    var chip: String = ""
    var chipRect: NSRect = .zero
    var preeditX: CGFloat = 0
    /// Page indicator glyph origins; nil when there is a single page.
    var pagerPrev: NSPoint?
    var pagerNext: NSPoint?
}

private final class CandidateView: NSView {
    private var state: EngineState = .empty
    private(set) var layout = CandidateLayout()

    private var candidateFont = NSFont.systemFont(ofSize: 18, weight: .medium)
    private var indexFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private var hintFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    private var noteFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    private var preeditFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    private var chipFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private var pagerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private var accent: NSColor = .systemRed
    private var horizontal = true
    private var showPreedit = false

    override var isFlipped: Bool { true }

    /// Called with the page-relative index of a clicked candidate.
    var onSelect: ((Int) -> Void)?

    // The panel never becomes key (clicking must not take focus from the
    // text client), so the first click has to be delivered directly.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = layout.items.firstIndex(where: { $0.rect.contains(point) }) {
            onSelect?(index)
        }
    }

    func update(state: EngineState, appearance: Config.Appearance) {
        self.state = state
        accent = appearance.accentColor.nsColor
        horizontal = (appearance.layout == .horizontal)
        showPreedit = appearance.showPreedit
        applyFont(appearance)
        layout = computeLayout()
        needsDisplay = true
    }

    private func applyFont(_ appearance: Config.Appearance) {
        let size = min(max(appearance.fontSize, 10), 32)
        // Font names come from user-editable config. Fall back instead of
        // rendering with a missing font after machines or macOS versions
        // differ from the one where the setting was saved.
        candidateFont = NSFont(name: appearance.font, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
        let small = max(10, (size * 0.68).rounded())
        indexFont = NSFont.monospacedDigitSystemFont(ofSize: small, weight: .medium)
        hintFont = NSFont.monospacedSystemFont(ofSize: small, weight: .semibold)
        noteFont = NSFont.systemFont(ofSize: small, weight: .regular)
        preeditFont = NSFont.monospacedSystemFont(ofSize: max(11, size - 4), weight: .medium)
        chipFont = NSFont.systemFont(ofSize: max(9, small - 1), weight: .semibold)
        pagerFont = NSFont.systemFont(ofSize: max(12, size - 3), weight: .semibold)
    }

    // MARK: Annotation

    /// Split a candidate's annotation into an emphasized "hint" and a
    /// secondary "note".
    ///
    /// For main-table candidates the hint is the part of the code *not yet
    /// typed* — the keys that would select this candidate — rather than the
    /// full code, whose typed prefix only repeats the preedit. For pinyin
    /// reverse lookup the annotation (the word's cqlb code) is the answer the
    /// user is looking for, so all of it is the hint.
    private func annotationParts(_ c: DisplayCandidate, typedLength: Int) -> (hint: String, note: String) {
        guard !c.annotation.isEmpty else { return ("", "") }
        switch c.source {
        case .main:
            guard c.annotation.hasPrefix(c.code) else { return ("", c.annotation) }
            let note = String(c.annotation.dropFirst(c.code.count)).trimmingCharacters(in: .whitespaces)
            let hint = String(c.code.dropFirst(min(typedLength, c.code.count)))
            return (hint, note)
        case .pinyin:
            return (c.annotation, "")
        default:
            return ("", c.annotation)
        }
    }

    // MARK: Layout

    private func width(_ s: String, _ font: NSFont) -> CGFloat {
        s.isEmpty ? 0 : ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    private func computeLayout() -> CandidateLayout {
        var l = CandidateLayout()
        let pad: CGFloat = 6
        let itemPad: CGFloat = 11
        let pointSize = candidateFont.pointSize
        let rowH = ceil(max(28, pointSize + 14))
        l.rowHeight = rowH

        // Header: always in pinyin / English / raw modes (the inline preedit
        // hides the mode prefix, so the chip is the only mode cue) and when
        // there is nothing else to show; in main mode only if enabled.
        let hasCandidates = !state.candidates.isEmpty
        let modal = state.keepsPreeditWithoutCandidates
        let showHeader = !state.preedit.isEmpty && (showPreedit || modal || !hasCandidates)
        let headerH: CGFloat = showHeader ? ceil(max(22, pointSize + 6)) : 0
        var headerW: CGFloat = 0
        if showHeader {
            if state.isPinyinMode { l.chip = "拼音" }
            else if state.isEnglishMode { l.chip = "英文" }
            else if state.isRawMode { l.chip = "原样" }
            var x = pad + itemPad - 2
            if !l.chip.isEmpty {
                let w = width(l.chip, chipFont) + 10
                let h = ceil(chipFont.pointSize + 6)
                l.chipRect = NSRect(x: x, y: pad + (headerH - h) / 2, width: w, height: h)
                x += w + 7
            }
            l.preeditX = x
            headerW = x + width(state.preedit, preeditFont) + itemPad + pad
        }

        // Measure items.
        let typedLength = state.preedit.count
        var items: [CandidateLayout.Item] = []
        var widths: [CGFloat] = []
        let indexColumn = width("8", indexFont)
        for (i, c) in state.candidates.enumerated() {
            var item = CandidateLayout.Item()
            item.index = "\(i + 1)"
            item.text = c.text
            let parts = annotationParts(c, typedLength: typedLength)
            item.hint = parts.hint
            item.note = parts.note
            var x = itemPad
            item.indexX = x
            x += indexColumn + 6
            item.textX = x
            x += width(c.text, candidateFont)
            if !item.hint.isEmpty {
                x += 6
                item.hintX = x
                x += width(item.hint, hintFont)
            }
            if !item.note.isEmpty {
                x += 6
                item.noteX = x
                x += width(item.note, noteFont)
            }
            x += itemPad
            items.append(item)
            widths.append(x)
        }

        let paged = state.hasPrevPage || state.hasNextPage
        let glyphW = width("‹", pagerFont)
        let top = pad + headerH + (showHeader && hasCandidates ? 2 : 0)

        if !hasCandidates {
            l.size = NSSize(width: min(max(headerW, 80), 800), height: pad + headerH + pad)
            l.panelRadius = min(l.size.height / 2, 14)
        } else if horizontal {
            var x = pad
            for i in items.indices {
                items[i].rect = NSRect(x: x, y: top, width: widths[i], height: rowH)
                x += widths[i] + 2
            }
            x -= 2
            if paged {
                x += 8
                l.pagerPrev = NSPoint(x: x, y: top)
                x += glyphW + 7
                l.pagerNext = NSPoint(x: x, y: top)
                x += glyphW + 6
            }
            let w = max(x + pad, headerW)
            l.size = NSSize(width: min(w, 800), height: top + rowH + pad)
            l.itemRadius = rowH / 2
            // Without a header the panel is one row tall: make it a capsule,
            // concentric with the capsule-shaped items.
            l.panelRadius = showHeader ? 16 : l.size.height / 2
        } else {
            let pagerH: CGFloat = paged ? ceil(pagerFont.pointSize + 8) : 0
            let contentW = min(max((widths.max() ?? 0), headerW - 2 * pad, 96), 520 - 2 * pad)
            var y = top
            for i in items.indices {
                items[i].rect = NSRect(x: pad, y: y, width: contentW, height: rowH)
                y += rowH
            }
            if paged {
                let mid = pad + contentW / 2
                l.pagerPrev = NSPoint(x: mid - glyphW - 7, y: y - (rowH - pagerH) / 2)
                l.pagerNext = NSPoint(x: mid + 7, y: y - (rowH - pagerH) / 2)
                y += pagerH
            }
            l.size = NSSize(width: contentW + 2 * pad, height: y + pad)
            l.itemRadius = min(10, rowH / 2)
            l.panelRadius = l.itemRadius + pad
        }

        if showHeader {
            l.headerRect = NSRect(x: 0, y: pad, width: l.size.width, height: headerH)
        }
        l.items = items
        if items.indices.contains(state.highlightedIndex) {
            l.highlightRect = items[state.highlightedIndex].rect
        }
        return l
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let l = layout

        if let header = l.headerRect {
            if !l.chip.isEmpty {
                accent.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: l.chipRect, xRadius: l.chipRect.height / 2, yRadius: l.chipRect.height / 2).fill()
                drawText(l.chip, font: chipFont, color: accent,
                         x: l.chipRect.minX + 5, centeredIn: l.chipRect)
            }
            drawText(state.preedit, font: preeditFont, color: accent, x: l.preeditX, centeredIn: header)
        }

        for (i, item) in l.items.enumerated() {
            let on = i == state.highlightedIndex
            // Text over the accent pill is white; elsewhere it uses the
            // semantic label colors so it adapts to light/dark.
            let primary: NSColor = on ? .white : .labelColor
            let dim: NSColor = on ? NSColor.white.withAlphaComponent(0.72) : .secondaryLabelColor
            let strong: NSColor = on ? .white : accent
            let r = item.rect
            drawText(item.index, font: indexFont, color: dim, x: r.minX + item.indexX, centeredIn: r)
            drawText(item.text, font: candidateFont, color: primary, x: r.minX + item.textX, centeredIn: r)
            if !item.hint.isEmpty {
                drawText(item.hint, font: hintFont, color: strong, x: r.minX + item.hintX, centeredIn: r)
            }
            if !item.note.isEmpty {
                drawText(item.note, font: noteFont, color: dim, x: r.minX + item.noteX, centeredIn: r)
            }
        }

        if let prev = l.pagerPrev, let next = l.pagerNext {
            let box = NSRect(x: 0, y: prev.y, width: 0, height: l.rowHeight)
            drawText("‹", font: pagerFont,
                     color: state.hasPrevPage ? .secondaryLabelColor : .quaternaryLabelColor,
                     x: prev.x, centeredIn: box)
            drawText("›", font: pagerFont,
                     color: state.hasNextPage ? .secondaryLabelColor : .quaternaryLabelColor,
                     x: next.x, centeredIn: box)
        }
    }

    /// Draw `text` at `x`, vertically centered in `box` by line height.
    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, centeredIn box: NSRect) {
        let lineH = font.ascender - font.descender
        (text as NSString).draw(
            at: NSPoint(x: x, y: box.minY + (box.height - lineH) / 2),
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }
}

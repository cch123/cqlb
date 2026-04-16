import AppKit
import CqlbCore

/// Non-activating floating panel that displays the engine's candidate list.
///
/// Look: the panel itself is transparent and hosts an `NSVisualEffectView`
/// as its content view (material `.hudWindow`), with the candidate content
/// view layered on top. This gives a native Liquid-Glass/vibrancy appearance
/// that blurs whatever's behind the window.
final class CandidateWindowController {
    static let shared = CandidateWindowController()

    private let window: NSPanel
    private let vfx: NSVisualEffectView
    private let view: CandidateView
    private let cornerRadius: CGFloat = 14
    private var lastSize: NSSize = .zero    // cache mask image
    private(set) var visible = false         // skip redundant order calls
    private var cachedMask: NSImage?

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
        panel.invalidateShadow()
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let vfx = NSVisualEffectView(frame: initialFrame)
        vfx.material = .menu
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        // Use maskImage instead of cornerRadius — this is the Apple-
        // recommended way to shape NSVisualEffectView and eliminates the
        // white corner artifacts that layer.cornerRadius leaves behind.
        vfx.maskImage = Self.roundedMask(size: initialFrame.size, radius: cornerRadius)
        vfx.autoresizingMask = [.width, .height]

        let content = CandidateView(frame: vfx.bounds)
        content.autoresizingMask = [.width, .height]
        vfx.addSubview(content)

        panel.contentView = vfx
        self.window = panel
        self.vfx = vfx
        self.view = content
    }

    func show(state: EngineState, near caretRect: NSRect) {
        view.update(state: state)
        let size = view.fittingContentSize()

        if size != lastSize {
            lastSize = size
            cachedMask = Self.roundedMask(size: size, radius: cornerRadius)
            vfx.maskImage = cachedMask
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height - 4)
        if caretRect.size == .zero || (caretRect.origin.x == 0 && caretRect.origin.y == 0) {
            origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.minY + 200
            )
        }
        if origin.x + size.width > screenFrame.maxX { origin.x = screenFrame.maxX - size.width - 8 }
        if origin.x < screenFrame.minX { origin.x = screenFrame.minX + 8 }
        if origin.y < screenFrame.minY { origin.y = screenFrame.minY + 8 }

        let newFrame = NSRect(origin: origin, size: size)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        } else {
            view.needsDisplay = true
        }
        if !visible {
            window.alphaValue = 1
            window.orderFrontRegardless()
            visible = true
        }
    }

    func hide() {
        guard visible else { return }
        // alphaValue=0 is near-instant (~0.01ms). orderOut triggers expensive
        // WindowServer recompositing for NSVisualEffectView (300-500ms spikes).
        window.alphaValue = 0
        visible = false
    }

    /// Build an `NSImage` mask with a rounded-rect hole. When set as
    /// `NSVisualEffectView.maskImage`, the VFX only draws inside the
    /// rounded rect — no white corner artifacts.
    private static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: radius,
                yRadius: radius
            ).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(
            top: radius, left: radius, bottom: radius, right: radius
        )
        img.resizingMode = .stretch
        return img
    }
}

private final class CandidateView: NSView {
    private var state: EngineState = .empty
    private let candidateFont = NSFont.systemFont(ofSize: 18, weight: .medium)
    private let indexFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private let annoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let preeditFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let hPad: CGFloat = 14
    private let vPad: CGFloat = 10
    private let rowH: CGFloat = 30
    private let preeditH: CGFloat = 24
    private var _accentColor: NSColor = .systemRed
    private var _horizontal: Bool = false

    override var isFlipped: Bool { true }

    func update(state: EngineState) {
        self.state = state
        let appearance = EngineHost.shared.currentConfig.appearance
        // Accent color
        switch appearance.accentColor {
        case .red:    _accentColor = .systemRed
        case .orange: _accentColor = .systemOrange
        case .green:  _accentColor = .systemGreen
        case .blue:   _accentColor = .systemBlue
        case .purple: _accentColor = .systemPurple
        case .teal:   _accentColor = .systemTeal
        }
        // Layout
        _horizontal = (appearance.layout == .horizontal)
        // Color scheme — applied on the window
        let panel = self.window
        switch appearance.colorScheme {
        case .system: panel?.appearance = nil
        case .light:  panel?.appearance = NSAppearance(named: .aqua)
        case .dark:   panel?.appearance = NSAppearance(named: .darkAqua)
        }
        needsDisplay = true
    }

    func fittingContentSize() -> NSSize {
        let textAttr: [NSAttributedString.Key: Any] = [.font: candidateFont]
        let annoAttr: [NSAttributedString.Key: Any] = [.font: annoFont]
        let count = state.candidates.count
        // Preedit width sets the minimum — important for English phrase mode
        // where the preedit can be much longer than any candidate.
        let preeditW = (state.preedit as NSString).size(withAttributes: [.font: preeditFont]).width
        let minWidth = max(160, preeditW + hPad * 2 + 16)
        if count == 0 {
            return NSSize(width: min(minWidth, 800), height: vPad + preeditH + vPad)
        }

        if _horizontal {
            // Mirror drawHorizontal's exact x-advance logic so width matches.
            let idxAttr: [NSAttributedString.Key: Any] = [.font: indexFont]
            var x: CGFloat = hPad
            for (i, c) in state.candidates.enumerated() {
                let idxW = ("\(i + 1)." as NSString).size(withAttributes: idxAttr).width
                x += idxW + 2
                x += (c.text as NSString).size(withAttributes: textAttr).width
                if !c.annotation.isEmpty {
                    x += (c.annotation as NSString).size(withAttributes: annoAttr).width + 4 + 4
                }
                if i < count - 1 { x += 12 }
            }
            x += hPad
            let totalW = x
            let h = vPad + preeditH + 4 + rowH + vPad
            return NSSize(width: min(max(totalW, minWidth), 800), height: h)
        } else {
            var maxWidth: CGFloat = minWidth
            for (_, c) in state.candidates.enumerated() {
                let textW = (c.text as NSString).size(withAttributes: textAttr).width
                let annoW = c.annotation.isEmpty ? 0 :
                    (c.annotation as NSString).size(withAttributes: annoAttr).width + 10
                maxWidth = max(maxWidth, hPad + 24 + textW + annoW + hPad + 8)
            }
            let h = vPad + preeditH + 4 + CGFloat(count) * rowH + vPad
            return NSSize(width: min(maxWidth, 520), height: h)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = vPad

        // ── Preedit line ──
        let preeditAttr: [NSAttributedString.Key: Any] = [
            .font: preeditFont,
            .foregroundColor: _accentColor.withAlphaComponent(0.9),
        ]
        (state.preedit as NSString).draw(
            at: NSPoint(x: hPad, y: y + 2),
            withAttributes: preeditAttr
        )
        y += preeditH

        // Separator line between preedit and candidates.
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: hPad, y: y))
        sep.line(to: NSPoint(x: bounds.width - hPad, y: y))
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        sep.lineWidth = 0.5
        sep.stroke()
        y += 4

        if state.candidates.isEmpty { return }

        let candH = candidateFont.ascender - candidateFont.descender
        let idxH  = indexFont.ascender - indexFont.descender
        let annoH = annoFont.ascender - annoFont.descender

        if _horizontal {
            drawHorizontal(y: y, candH: candH, idxH: idxH, annoH: annoH)
        } else {
            drawVertical(y: y, candH: candH, idxH: idxH, annoH: annoH)
        }
    }

    private func drawHorizontal(y startY: CGFloat, candH: CGFloat, idxH: CGFloat, annoH: CGFloat) {
        var x: CGFloat = hPad
        let y = startY
        let textAttr: [NSAttributedString.Key: Any] = [
            .font: candidateFont,
            .foregroundColor: NSColor.labelColor,
        ]
        for (i, c) in state.candidates.enumerated() {
            let idxAttr: [NSAttributedString.Key: Any] = [
                .font: indexFont,
                .foregroundColor: i == 0 ? _accentColor : NSColor.secondaryLabelColor,
            ]
            let idxStr = "\(i + 1)." as NSString
            let idxW = idxStr.size(withAttributes: idxAttr).width
            idxStr.draw(at: NSPoint(x: x, y: y + (rowH - idxH) / 2), withAttributes: idxAttr)
            x += idxW + 2

            let textStr = c.text as NSString
            let textW = textStr.size(withAttributes: textAttr).width
            textStr.draw(at: NSPoint(x: x, y: y + (rowH - candH) / 2), withAttributes: textAttr)
            x += textW

            if !c.annotation.isEmpty {
                let annoAttr: [NSAttributedString.Key: Any] = [
                    .font: annoFont,
                    .foregroundColor: _accentColor.withAlphaComponent(0.85),
                ]
                let annoStr = c.annotation as NSString
                let annoW = annoStr.size(withAttributes: annoAttr).width
                annoStr.draw(at: NSPoint(x: x + 4, y: y + (rowH - annoH) / 2 + 1), withAttributes: annoAttr)
                x += annoW + 4
            }
            x += 12  // gap between candidates
        }
    }

    private func drawVertical(y startY: CGFloat, candH: CGFloat, idxH: CGFloat, annoH: CGFloat) {
        var y = startY
        for (i, c) in state.candidates.enumerated() {
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: rowH)

            if i == 0 {
                let pill = NSBezierPath(
                    roundedRect: rowRect.insetBy(dx: 6, dy: 1),
                    xRadius: 8, yRadius: 8
                )
                _accentColor.withAlphaComponent(0.12).setFill()
                pill.fill()
            }

            let idxAttr: [NSAttributedString.Key: Any] = [
                .font: indexFont,
                .foregroundColor: i == 0 ? _accentColor : NSColor.secondaryLabelColor,
            ]
            ("\(i + 1)" as NSString).draw(
                at: NSPoint(x: hPad, y: y + (rowH - idxH) / 2),
                withAttributes: idxAttr
            )

            let textX: CGFloat = hPad + 24
            let textAttr: [NSAttributedString.Key: Any] = [
                .font: candidateFont,
                .foregroundColor: NSColor.labelColor,
            ]
            let textStr = c.text as NSString
            textStr.draw(
                at: NSPoint(x: textX, y: y + (rowH - candH) / 2),
                withAttributes: textAttr
            )

            if !c.annotation.isEmpty {
                // Place anno right after text — one measurement per candidate
                // (unavoidable for horizontal alignment, but cheaper than before).
                let tw = textStr.size(withAttributes: textAttr).width
                let annoAttr: [NSAttributedString.Key: Any] = [
                    .font: annoFont,
                    .foregroundColor: _accentColor.withAlphaComponent(0.85),
                ]
                (c.annotation as NSString).draw(
                    at: NSPoint(x: textX + tw + 10, y: y + (rowH - annoH) / 2 + 1),
                    withAttributes: annoAttr
                )
            }

            y += rowH
        }
    }
}

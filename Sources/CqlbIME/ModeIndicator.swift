import AppKit
import CqlbCore

extension Config.Appearance.AccentColor {
    var nsColor: NSColor {
        switch self {
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .purple: return .systemPurple
        case .teal:   return .systemTeal
        }
    }
}

/// Shows a brief indicator when switching between Chinese / English mode.
/// Modelled on the macOS 14+ system input-source indicator: a compact
/// accent-tinted badge anchored directly below the text caret, which fades
/// in, stays for about a second and fades out.
final class ModeIndicator {
    static let shared = ModeIndicator()

    private static let size = NSSize(width: 28, height: 24)
    private static let cornerRadius: CGFloat = 6
    private static let caretGap: CGFloat = 3
    private static let visibleDuration: TimeInterval = 1.0
    private static let fadeInDuration: TimeInterval = 0.12
    private static let fadeOutDuration: TimeInterval = 0.25

    private let window: NSPanel
    private let tint: NSView
    private let label: NSTextField
    private var hideTimer: Timer?
    /// Incremented on every `show`; lets a fade-out completion handler detect
    /// that a newer `show` superseded it and skip its `orderOut`.
    private var generation = 0

    private init() {
        let frame = NSRect(origin: .zero, size: Self.size)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let vfx = NSVisualEffectView(frame: frame)
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        // A mask image (rather than layer.cornerRadius) makes the window
        // server clip both the blur and the window shadow to the rounded
        // shape, so no rectangular shadow corners remain visible.
        vfx.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        vfx.autoresizingMask = [.width, .height]

        let tintView = NSView(frame: frame)
        tintView.wantsLayer = true
        tintView.autoresizingMask = [.width, .height]
        vfx.addSubview(tintView)

        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 13, weight: .medium)
        tf.alignment = .center
        tf.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.centerXAnchor.constraint(equalTo: vfx.centerXAnchor),
            tf.centerYAnchor.constraint(equalTo: vfx.centerYAnchor),
        ])

        panel.contentView = vfx
        self.window = panel
        self.tint = tintView
        self.label = tf
    }

    func show(chinese: Bool, near caretRect: NSRect = .zero) {
        hideTimer?.invalidate()
        generation += 1
        let current = generation

        // Explicitly follow the current system appearance. NSPanels
        // without a parent window don't automatically inherit dark mode —
        // they stick on whatever appearance they had when first shown.
        let appearance = NSApp.effectiveAppearance
        window.appearance = appearance

        // Same glyphs as the system indicator: "A" for the Latin layout, a
        // single CJK character for the Chinese input mode. Both modes use
        // the accent colour; the glyph alone distinguishes them.
        label.stringValue = chinese ? "中" : "A"
        let accent = EngineHost.shared.currentConfig.appearance.accentColor.nsColor
        label.textColor = accent
        // CGColor is not dynamic, so resolve it under the current appearance.
        appearance.performAsCurrentDrawingAppearance {
            tint.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
        }

        let screen = Self.screen(containing: caretRect)
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        window.setFrameOrigin(Self.origin(near: caretRect, in: screen.visibleFrame, size: window.frame.size))

        if !window.isVisible {
            window.alphaValue = 0
        }
        window.orderFrontRegardless()
        window.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeInDuration
            window.animator().alphaValue = 1
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeOutDuration
                self?.window.animator().alphaValue = 0
            } completionHandler: {
                guard let self, self.generation == current else { return }
                self.window.orderOut(nil)
            }
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        guard isUsable(rect) else { return nil }
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private static func origin(near caretRect: NSRect, in screenFrame: NSRect, size: NSSize) -> NSPoint {
        let margin: CGFloat = 4

        guard isUsable(caretRect) else {
            return NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2 + 120
            )
        }

        var origin = NSPoint(
            x: caretRect.midX - size.width / 2,
            y: caretRect.minY - size.height - caretGap
        )

        if origin.y < screenFrame.minY + margin {
            origin.y = caretRect.maxY + caretGap
        }
        if origin.x + size.width > screenFrame.maxX - margin {
            origin.x = screenFrame.maxX - size.width - margin
        }
        if origin.x < screenFrame.minX + margin {
            origin.x = screenFrame.minX + margin
        }
        if origin.y + size.height > screenFrame.maxY - margin {
            origin.y = screenFrame.maxY - size.height - margin
        }
        if origin.y < screenFrame.minY + margin {
            origin.y = screenFrame.minY + margin
        }
        return origin
    }

    private static func isUsable(_ rect: NSRect) -> Bool {
        if rect.origin.x.isNaN || rect.origin.y.isNaN { return false }
        if rect.size.width.isNaN || rect.size.height.isNaN { return false }
        if rect.origin.x == 0 && rect.origin.y == 0 && rect.size == .zero { return false }
        return true
    }
}

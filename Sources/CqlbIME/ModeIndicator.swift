import AppKit

/// Shows a brief floating indicator when switching between Chinese / English
/// mode. Appears near the active text caret, fades out after ~0.8 seconds.
final class ModeIndicator {
    static let shared = ModeIndicator()

    private let window: NSPanel
    private let label: NSTextField
    private var hideTimer: Timer?

    private init() {
        let w: CGFloat = 140
        let h: CGFloat = 60
        let frame = NSRect(x: 0, y: 0, width: w, height: h)

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
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let vfx = NSVisualEffectView(frame: frame)
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 16
        vfx.layer?.masksToBounds = true
        vfx.autoresizingMask = [.width, .height]

        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 24, weight: .semibold)
        tf.textColor = .labelColor
        tf.alignment = .center
        tf.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.centerXAnchor.constraint(equalTo: vfx.centerXAnchor),
            tf.centerYAnchor.constraint(equalTo: vfx.centerYAnchor),
        ])

        panel.contentView = vfx
        self.window = panel
        self.label = tf
    }

    func show(chinese: Bool, near caretRect: NSRect = .zero) {
        hideTimer?.invalidate()
        // Explicitly follow the current system appearance. NSPanels
        // without a parent window don't automatically inherit dark mode —
        // they stick on whatever appearance they had when first shown.
        window.appearance = NSApp.effectiveAppearance
        label.stringValue = chinese ? "中" : "英"
        label.textColor = chinese ? .systemRed : .labelColor

        let screen = Self.screen(containing: caretRect)
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        window.setFrameOrigin(Self.origin(near: caretRect, in: screen.visibleFrame, size: window.frame.size))
        window.alphaValue = 1.0
        window.orderFrontRegardless()

        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self?.window.animator().alphaValue = 0
            } completionHandler: {
                self?.window.orderOut(nil)
            }
        }
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        guard isUsable(rect) else { return nil }
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private static func origin(near caretRect: NSRect, in screenFrame: NSRect, size: NSSize) -> NSPoint {
        let margin: CGFloat = 8

        guard isUsable(caretRect) else {
            return NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2 + 120
            )
        }

        var origin = NSPoint(
            x: caretRect.midX - size.width / 2,
            y: caretRect.minY - size.height - margin
        )

        if origin.y < screenFrame.minY + margin {
            origin.y = caretRect.maxY + margin
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

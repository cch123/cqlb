import AppKit

/// Shows a brief floating indicator when switching between Chinese / English
/// mode. Appears at screen center, fades out after ~0.8 seconds.
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

    func show(chinese: Bool) {
        hideTimer?.invalidate()
        label.stringValue = chinese ? "中" : "英"
        label.textColor = chinese ? .systemRed : .labelColor

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = screen.frame.midX - window.frame.width / 2
        let y = screen.frame.midY - window.frame.height / 2 + 120
        window.setFrameOrigin(NSPoint(x: x, y: y))
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
}

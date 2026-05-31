import AppKit
import SwiftUI
import CqlbCore

@Observable
final class SettingsModel {
    var config: Config
    var isDirty: Bool = false

    private let onSave: (() -> Void)?
    private var savedConfig: Config

    init(onSave: (() -> Void)? = nil) {
        let config = ConfigStore.load()
        self.config = config
        self.savedConfig = config
        self.onSave = onSave
    }

    func markDirty() {
        isDirty = (config != savedConfig)
    }

    func save() {
        do {
            try ConfigStore.save(config)
            savedConfig = config
            isDirty = false
            onSave?()
        } catch {
            NSLog("[cqlb-settings-ui] save failed: %@", String(describing: error))
        }
    }

    func revert() {
        config = savedConfig
        isDirty = false
    }
}

public struct SettingsContentView: View {
    @State private var model: SettingsModel

    public init(onSave: (() -> Void)? = nil) {
        _model = State(initialValue: SettingsModel(onSave: onSave))
    }

    public var body: some View {
        RootView(model: model)
            .frame(minWidth: 780, minHeight: 560)
    }
}

@MainActor
public final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var restoreAccessoryPolicyOnClose = false

    private override init() {}

    public func show(onSave: (() -> Void)? = nil) {
        prepareForForegroundWindow()

        if let window {
            present(window)
            return
        }

        let content = SettingsContentView(onSave: onSave)
        let hostingController = NSHostingController(rootView: content)
        // Avoid NSWindow(contentViewController:): on macOS 26, an IME process
        // can crash inside AppKit's private title binding setup for that
        // convenience initializer. Creating the window first and assigning the
        // controller afterward bypasses the binding path while keeping the
        // same visible window behavior.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "超强两笔 · 设置"
        window.minSize = NSSize(width: 780, height: 560)
        window.setContentSize(NSSize(width: 780, height: 560))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.center()

        self.window = window
        present(window)
    }

    private func prepareForForegroundWindow() {
        guard NSApp.activationPolicy() != .regular else { return }

        // The IME normally runs as an accessory LSUIElement process. That is
        // correct for typing, but normal NSWindow presentation from an IME
        // menu is unreliable while the process cannot become a regular
        // foreground app. Promote only while Settings is open; closing the
        // window restores the input method to accessory mode.
        restoreAccessoryPolicyOnClose = true
        NSApp.setActivationPolicy(.regular)
    }

    private func present(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Even after activation, IME windows can be ordered behind the text
        // client that triggered the menu. Force ordering after makeKey so the
        // menu command has a deterministic visible result.
        window.orderFrontRegardless()
        window.makeMain()
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        if restoreAccessoryPolicyOnClose {
            restoreAccessoryPolicyOnClose = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

import AppKit
import SwiftUI
import CqlbCore

/// Settings state. Edits apply immediately: every change schedules a
/// debounced write of `config.json`, which the IME picks up at once.
@Observable
final class SettingsModel {
    var config: Config

    private let onSave: (() -> Void)?
    private var savedConfig: Config
    private var pendingSave: DispatchWorkItem?

    init(onSave: (() -> Void)? = nil) {
        let config = ConfigStore.load()
        self.config = config
        self.savedConfig = config
        self.onSave = onSave
    }

    /// Coalesce bursts of changes (e.g. dragging the font-size slider) into
    /// one file write.
    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Write pending changes now. Called when the window closes.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard config != savedConfig else { return }
        do {
            try ConfigStore.save(config)
            savedConfig = config
            onSave?()
        } catch {
            NSLog("[cqlb-settings-ui] save failed: %@", String(describing: error))
        }
    }
}

public struct SettingsContentView: View {
    @State private var model: SettingsModel

    public init(onSave: (() -> Void)? = nil) {
        _model = State(initialValue: SettingsModel(onSave: onSave))
    }

    init(model: SettingsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        RootView(model: model)
            .frame(minWidth: 700, minHeight: 520)
    }
}

@MainActor
public final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var model: SettingsModel?
    private var restoreAccessoryPolicyOnClose = false

    private override init() {}

    public func show(onSave: (() -> Void)? = nil) {
        prepareForForegroundWindow()

        if let window {
            present(window)
            return
        }

        let model = SettingsModel(onSave: onSave)
        self.model = model
        let content = SettingsContentView(model: model)
        let hostingController = NSHostingController(rootView: content)
        // Avoid NSWindow(contentViewController:): on macOS 26, an IME process
        // can crash inside AppKit's private title binding setup for that
        // convenience initializer. Creating the window first and assigning the
        // controller afterward bypasses the binding path while keeping the
        // same visible window behavior.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        // The title still names the window in Mission Control and the Window
        // menu, but is not drawn: content runs edge to edge under a
        // transparent title bar, and the window can be dragged by any empty
        // area since there is no visible title bar to grab.
        window.title = "超强两笔设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar moves the traffic-light buttons down and
        // inward to the standard position, so they sit inside the floating
        // sidebar panel instead of on its rounded corner.
        let toolbar = NSToolbar(identifier: "cqlb.settings")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 520)
        window.setContentSize(NSSize(width: 780, height: 620))
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
        // Changes save as they are made; flush the debounce window so the
        // last edit before closing is not lost.
        model?.flush()
        window = nil
        model = nil
        if restoreAccessoryPolicyOnClose {
            restoreAccessoryPolicyOnClose = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

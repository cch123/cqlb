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

    private override init() {}

    public func show(onSave: (() -> Void)? = nil) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = SettingsContentView(onSave: onSave)
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "超强两笔 · 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 780, height: 560)
        window.setContentSize(NSSize(width: 780, height: 560))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

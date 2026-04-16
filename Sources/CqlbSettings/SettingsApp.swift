import SwiftUI
import CqlbCore

@Observable
final class SettingsModel {
    var config: Config
    var isDirty: Bool = false

    init() {
        self.config = ConfigStore.load()
    }

    func markDirty() {
        isDirty = true
    }

    func save() {
        do {
            try ConfigStore.save(config)
            isDirty = false
        } catch {
            NSLog("[cqlb-settings] save failed: %@", String(describing: error))
        }
    }

    func revert() {
        config = ConfigStore.load()
        isDirty = false
    }
}

@main
struct CqlbSettingsApp: App {
    @State private var model = SettingsModel()

    var body: some Scene {
        WindowGroup("超强两笔 · 设置") {
            RootView(model: model)
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}

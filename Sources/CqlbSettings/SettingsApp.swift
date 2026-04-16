import SwiftUI
import CqlbCore

@Observable
final class SettingsModel {
    var config: Config {
        didSet {
            guard config != oldValue else { return }
            do {
                try ConfigStore.save(config)
            } catch {
                NSLog("[cqlb-settings] save failed: %@", String(describing: error))
            }
        }
    }

    init() {
        self.config = ConfigStore.load()
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

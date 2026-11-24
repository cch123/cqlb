import AppKit
import CqlbSettingsUI

// Development tool: host the settings window as a standalone app, so the
// settings UI can be iterated on without reinstalling the input method.
//
//   make preview
//   CQLB_SETTINGS_PANE=功能 .build/debug/cqlb-settings-preview --snapshot out.png
//
// Build through `make preview`, not bare `swift run`: the Makefile links
// against the real SDK version, without which AppKit renders the legacy
// control appearance (see LINK_SDK_FLAGS in the Makefile).
//
// It reads and writes the real config file, exactly like the IME does.

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CQLB_SETTINGS_APPEARANCE=light|dark forces an appearance, to check
        // both without changing the system setting.
        switch ProcessInfo.processInfo.environment["CQLB_SETTINGS_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        SettingsWindowPresenter.shared.show()

        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let output = URL(fileURLWithPath: args[i + 1])
        // Give SwiftUI a moment to lay out and finish the first render pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            defer { NSApp.terminate(nil) }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = PreviewDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

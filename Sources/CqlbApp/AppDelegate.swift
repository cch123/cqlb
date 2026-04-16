import AppKit
import ApplicationServices

/// Owns the application lifecycle: checks Accessibility permission, starts
/// the event tap, installs a menu bar status item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var eventTap: EventTap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.general.log("applicationDidFinishLaunching pid=\(getpid())")
        installStatusItem()

        // Warm the engine now so the first keystroke doesn't pay dictionary
        // parsing cost.
        _ = EngineHost.shared

        let trusted = ensureAccessibilityPermission()
        Log.general.log("accessibility trusted=\(trusted)")
        if !trusted {
            showAccessibilityAlert()
            return
        }
        startEventTap()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "两"
            button.toolTip = "超强两笔 — ⌥Space 切换"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "超强两笔 (cqlb)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settingsItem = menu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "重新打开辅助功能权限设置…",
            action: #selector(openAccessibilityPrefs),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 cqlb",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openSettings() {
        // Try a few likely locations for the Settings bundle — the install
        // path first, then a sibling next to the cqlb binary for ad-hoc
        // builds.
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Applications/cqlb Settings.app"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/cqlb Settings.app"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("cqlb Settings.app"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
                if let error = error {
                    Log.general.error("open settings failed: \(error)")
                }
            }
            return
        }
        Log.general.error("cqlb Settings.app not found in any known location")
        let alert = NSAlert()
        alert.messageText = "找不到设置 App"
        alert.informativeText = "cqlb Settings.app 应该装在 ~/Applications 或 /Applications。请重新运行 ./dev.sh。"
        alert.runModal()
    }

    // MARK: - Accessibility permission

    private func ensureAccessibilityPermission() -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        cqlb 需要"辅助功能"权限才能全局监听键盘输入。

        请到 系统设置 → 隐私与安全性 → 辅助功能,勾选 cqlb,然后重启 cqlb。
        """
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            openAccessibilityPrefs()
        }
    }

    @objc private func openAccessibilityPrefs() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Event tap

    private func startEventTap() {
        let tap = EventTap()
        do {
            try tap.start()
            self.eventTap = tap
        } catch {
            Log.tap.error("failed to start event tap: \(error)")
            let alert = NSAlert()
            alert.messageText = "无法启动键盘监听"
            alert.informativeText = "\(error.localizedDescription)\n\n请确认已授予 cqlb 辅助功能权限,并重启 cqlb。"
            alert.runModal()
        }
    }
}

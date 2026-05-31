import AppKit
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.general.log("NSApplication did finish launching")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// Keep a strong reference so IMKServer isn't deallocated while the run
// loop is alive. The connection name MUST match the
// `InputMethodConnectionName` key in Info.plist.
var server: IMKServer?
let appDelegate = AppDelegate()

autoreleasepool {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.cqlb.inputmethod"
    let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
        ?? "cqlb_Connection"
    Log.general.log("cqlb-ime entered main (bundle=\(bundleId), connection=\(connectionName))")
    NSApplication.shared.delegate = appDelegate
    Log.general.log("cqlb-ime starting (bundle=\(bundleId), connection=\(connectionName))")
    server = IMKServer(name: connectionName, bundleIdentifier: bundleId)
    // Warm dictionaries and engine before the first keystroke arrives.
    _ = EngineHost.shared
}

// IMK apps don't get a Dock icon; `.accessory` matches that expectation.
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
Log.general.error("NSApplication.run returned unexpectedly")
RunLoop.main.run()

import AppKit
import InputMethodKit

// Keep a strong reference so IMKServer isn't deallocated while the run
// loop is alive. The connection name MUST match the
// `InputMethodConnectionName` key in Info.plist.
var server: IMKServer?

autoreleasepool {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.cqlb.inputmethod"
    let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
        ?? "com.cqlb.inputmethod_Connection"
    Log.general.log("cqlb-ime starting (bundle=\(bundleId), connection=\(connectionName))")
    server = IMKServer(name: connectionName, bundleIdentifier: bundleId)
    // Warm dictionaries and engine before the first keystroke arrives.
    _ = EngineHost.shared
}

// IMK apps don't get a Dock icon; `.accessory` matches that expectation.
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

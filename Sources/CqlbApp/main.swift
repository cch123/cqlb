import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Run as an "accessory" app: no Dock icon, still has a menu bar presence.
app.setActivationPolicy(.accessory)
app.run()

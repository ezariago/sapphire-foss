import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Sapphire shield fixture"
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()

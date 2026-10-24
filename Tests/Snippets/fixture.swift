import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Sapphire snippet test fixture"
let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
let text = NSTextView(frame: NSRect(x: 10, y: 55, width: 400, height: 115))
text.isRichText = false
text.string = ";hello "
text.setSelectedRange(NSRange(location: 7, length: 0))
content.addSubview(text)
let secure = NSSecureTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 25))
secure.stringValue = "synthetic fixture only"
content.addSubview(secure)
window.contentView = content
window.makeFirstResponder(text)
window.orderBack(nil) // Never activate or focus over the user's application.
_ = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in app.terminate(nil) }
app.run()

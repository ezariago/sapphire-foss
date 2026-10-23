import AppKit
import SwiftUI

enum FocusIntensity { case minimal, gentle, standard, strict }
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtureID = "dev.sapphire.shield-fixture"
let blocker = AppBlocker()
var allowed = false
var fixture: NSRunningApplication?
blocker.isBlocked = { $0 == fixtureID && !allowed }
blocker.makeShieldContent = { name, _ in AnyView(Text("Shielding \(name)")) }
blocker.setBlocking(true)
let config = NSWorkspace.OpenConfiguration()
config.activates = true
NSWorkspace.shared.openApplication(at: fixtureURL, configuration: config) { app, error in
    DispatchQueue.main.async {
        guard let app, error == nil else { fatalError("Could not launch fixture: \(String(describing: error))") }
        fixture = app
    }
}
var tries = 0
_ = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
    MainActor.assumeIsolated {
        tries += 1
        if fixture != nil && blocker.isShielded(fixtureID) {
            assert(NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
            allowed = true
            blocker.refresh()
            assert(!blocker.isShielded(fixtureID))
            allowed = false
            blocker.shield(bundleID: fixtureID)
            assert(blocker.isShielded(fixtureID))
            blocker.setBlocking(false)
            assert(!blocker.isBlocking && !blocker.isShielded(fixtureID))
            assert(!NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
            fixture?.terminate()
            timer.invalidate()
            print("Passed real app activation, shield display, unblock, reblock and teardown checks.")
            exit(0)
        }
        if tries >= 40 {
            blocker.setBlocking(false)
            fixture?.terminate()
            fatalError("Fixture never received a shield")
        }
    }
}
}
application.run()

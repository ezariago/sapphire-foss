import AppKit
import SwiftUI

enum FocusIntensity { case minimal, gentle, standard, strict }
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let panelOnly = CommandLine.arguments.contains("--panel-only")
let fixtureID = "dev.sapphire.shield-fixture"
var frames = NSScreen.screens.map(\.frame)
let blocker = AppBlocker(screenFrames: { frames })
var allowed = false
var fixture: NSRunningApplication?
blocker.isBlocked = { $0 == fixtureID && !allowed }
blocker.makeShieldContent = { name, _ in AnyView(Text("Shielding \(name)")) }
blocker.setBlocking(true)
let config = NSWorkspace.OpenConfiguration()
config.activates = !panelOnly
config.arguments = panelOnly ? ["--background"] : []
NSWorkspace.shared.openApplication(at: fixtureURL, configuration: config) { app, error in
    DispatchQueue.main.async {
        guard let app, error == nil else { fatalError("Could not launch fixture: \(String(describing: error))") }
        fixture = app
        if panelOnly { blocker.shield(bundleID: fixtureID) }
    }
}
blocker.keepsShieldWhenNotFrontmost = { _ in panelOnly }
var tries = 0
_ = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
    MainActor.assumeIsolated {
        tries += 1
        if panelOnly, fixture != nil { blocker.shield(bundleID: fixtureID) }
        if fixture != nil && blocker.isShielded(fixtureID) {
            assert(NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
            let originalFrames = frames
            frames[0] = frames[0].insetBy(dx: 7, dy: 9)
            blocker.refresh()
            assert(NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver && $0.frame == frames[0] })
            frames = originalFrames
            blocker.refresh()
            assert(NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver && $0.frame == frames[0] })
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
            print("Passed \(panelOnly ? "explicit fixture shielding (activation not tested)" : "real app activation"), shield display/simulated display-layout changes, unblock, reblock and teardown checks.")
            exit(0)
        }
        if tries >= 40 {
            blocker.setBlocking(false)
            fixture?.terminate()
            fatalError("Fixture never received a shield; front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"), fixtureHidden=\(fixture?.isHidden.description ?? "nil"), policy=\(fixture?.activationPolicy.rawValue ?? -1)")
        }
    }
}
}
application.run()

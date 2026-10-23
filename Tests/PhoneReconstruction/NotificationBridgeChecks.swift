import AppKit
import SwiftUI
import Combine

enum ActivityType { case none, continuityNotification, music }
enum TestContent {
    case none, full(AnyHashable)
    var id: AnyHashable? { if case .full(let id) = self { return id }; return nil }
}
struct TestSettings { var continuityNotificationsAsBanners = false; var continuityNotificationMutedApps: [String: String] = [:] }
@MainActor final class SettingsModel { static let shared = SettingsModel(); var current = TestSettings() }
@MainActor final class ContinuityManager { static let shared = ContinuityManager(); var activePeerID: String? = "fixture" }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let liveActivityManager = TestManager()
    func revertNotchWindowFocus() {}
}
@main struct Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        let app = AppDelegate()
        NSApp.delegate = app
        let bridge = ContinuityNotificationBridge()
        func entry(_ key: String, revision: String = "v1") -> PhoneNotification {
            PhoneNotification(payload: ["key": .string(key), "revision": .string(revision),
                "appId": .string("fixture.app"), "title": .string("Local test"), "clearable": .bool(true)])!
        }
        let a = entry("a"), a2 = entry("a2")
        let allowedPayload: [String: PhoneJSON] = ["key": .string("b"), "revision": .string("v1"), "appId": .string("other.app"), "title": .string("Other app")]
        let b = PhoneNotification(payload: allowedPayload)!
        bridge.accept(a); bridge.accept(a2); bridge.accept(b)
        bridge.composingNotificationID = a.id
        let request = bridge.beginAction(for: a)!
        app.liveActivityManager.currentActivity = .continuityNotification
        app.liveActivityManager.activityContent = .full("continuity-notif-\(a.id)")
        SettingsModel.shared.current.continuityNotificationMutedApps = [a.appId: a.appName]
        bridge.removeMutedApps([a.appId])
        precondition(bridge.notifications == [b] && bridge.latest == b, "Only an allowed app may be promoted after muting")
        precondition(bridge.composingNotificationID == nil && bridge.actionRequestID == nil && bridge.actionKey == nil)
        precondition(app.liveActivityManager.currentActivity == .none)
        bridge.finishAction(requestID: request, message: "Late result")
        precondition(bridge.actionStatus.isEmpty, "Late action replies cannot overwrite cleared state")
        bridge.accept(a)
        precondition(bridge.notifications == [b], "Muted live events must be ignored")
        bridge.removeMutedApps([a.appId])
        precondition(bridge.latest == b, "Repeated mute must preserve allowed alerts")
        bridge.reset()
        bridge.accept(a)
        precondition(bridge.notifications.isEmpty, "Mute persists across reset")
        SettingsModel.shared.current.continuityNotificationMutedApps = [:]
        let snapshotPayload: [String: PhoneJSON] = ["key": .string("a"), "revision": .string("v1"), "appId": .string(a.appId), "title": .string("Restored"), "snapshot": .bool(true)]
        bridge.accept(PhoneNotification(payload: snapshotPayload)!)
        precondition(bridge.notifications.count == 1 && bridge.latest == nil, "Unmuted snapshot restores quietly")
        bridge.reset()
        bridge.accept(b); bridge.accept(a)
        let allowedRequest = bridge.beginAction(for: b)!
        bridge.composingNotificationID = b.id
        app.liveActivityManager.currentActivity = .music
        app.liveActivityManager.activityContent = .full("music")
        bridge.removeMutedApps([a.appId])
        precondition(bridge.latest == b && bridge.composingNotificationID == b.id && bridge.actionRequestID == allowedRequest)
        precondition(app.liveActivityManager.currentActivity == .music, "Muting a queued app must preserve unrelated activities")
        bridge.reset()
        print("PASS: selective mute, queue promotion, activity/composer cleanup, pending action cancellation, late result rejection, reconnect filtering, quiet restore, unrelated activity/action preservation")
        withExtendedLifetime(app) {}
    }
}

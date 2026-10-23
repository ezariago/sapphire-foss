#!/usr/bin/env python3
"""Run Mac notification lifecycle checks against the production bridge and dismissal method."""
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "build" / "notification-bridge-tests"
OUTPUT.mkdir(parents=True, exist_ok=True)

def section(path, start, end):
    source = (ROOT / path).read_text()
    first = source.index(start)
    return source[first:source.index(end, first)]

bridge = section("Sapphire/Stubs/ContinuityCore.swift",
                 "@MainActor\nfinal class ContinuityNotificationBridge:",
                 "@MainActor\nfinal class ContinuityExternalActivityBridge:")
(OUTPUT / "Bridge.swift").write_text(
    "import AppKit\nimport SwiftUI\nimport Combine\nimport CryptoKit\nimport UserNotifications\n"
    "typealias ContinuityMirroredNotification = PhoneNotification\n" + bridge)
dismiss = section("Sapphire/LiveActivities/LiveActivityManager.swift",
                  "    func dismissContinuityNotification(id: String)",
                  "    func dismissCurrentActivity()")
(OUTPUT / "Manager.swift").write_text("""import AppKit
import Foundation
@MainActor final class TestManager {
    var currentActivity: ActivityType = .none
    var activityContent: TestContent = .none
    var lastEvalTime = 1.0
    func setActivity(type: ActivityType, content: TestContent) { currentActivity = type; activityContent = content }
    func evaluateAndDisplayActivity(allowImmediateDismiss: Bool) {}
""" + dismiss + "\n}\n")
app = OUTPUT / "Notification Bridge Checks.app" / "Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
(app / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "dev.sapphire.notification-bridge-checks",
    "CFBundleExecutable": "NotificationBridgeChecks",
    "CFBundleName": "Notification Bridge Checks",
    "CFBundlePackageType": "APPL", "LSUIElement": True,
}))
executable = app / "MacOS" / "NotificationBridgeChecks"
environment = os.environ.copy()
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
subprocess.run(["xcrun", "swiftc",
                str(ROOT / "Sapphire/Reconstruction/PhoneWire.swift"),
                str(ROOT / "Sapphire/Reconstruction/PhoneNotifications.swift"),
                str(OUTPUT / "Bridge.swift"), str(OUTPUT / "Manager.swift"),
                str(ROOT / "Tests/PhoneReconstruction/NotificationBridgeChecks.swift"),
                "-o", str(executable)], env=environment, check=True)
subprocess.run([str(executable)], env=environment, check=True)

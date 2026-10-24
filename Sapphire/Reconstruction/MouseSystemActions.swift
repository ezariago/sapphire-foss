#if !SAPPHIRE_FULL_BUILD
import AppKit

/// Fixed OS-owned target; no shell, AppleScript, custom URL, key posting or arbitrary executable.
enum MouseSystemActions {
    private static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app", isDirectory: true)
    static func missionControlTarget(identity: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> URL? {
        identity(missionControl) == "com.apple.exposelauncher" ? missionControl : nil
    }
    @MainActor static func requestMissionControl(validate: () -> Bool,
        identity: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier },
        open: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        guard let target = missionControlTarget(identity: identity), validate() else { return false }
        return open(target)
    }
}
#endif

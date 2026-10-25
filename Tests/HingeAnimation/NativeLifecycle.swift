import AppKit
import Combine
struct Settings {
    var systemEnhanceHingeAnimationEnabled = false
    var systemEnhanceHingeAnimationActivationAngle = 90.0
    var systemEnhanceHingeAnimationIntensity = 1.0
    var systemEnhanceHingeAnimationBlur = 135.0
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    @Published var settings = Settings()
    var current: Settings { settings }
}
@MainActor final class LidAngleSensor {
    enum Client { case hingeAnimation, hingeAnimationStandby }
    static let shared = LidAngleSensor()
    @Published var tick: UInt = 0
    var angle = 120.0
    var isAvailable = false
    var isReporting = false
    private(set) var acquisitions = 0
    func acquire(_ client: Client) { acquisitions += 1 }
    func release(_ client: Client) {}
}
@main struct NativeLifecycle {
    @MainActor static func main() {
        _ = NSApplication.shared
        let manager = SystemEnhanceHingeAnimationManager.shared
        manager.start(); manager.start()
        assert(manager.status == HingeAnimationPhase.disabled.message)
        assert(!manager.needsScreenRecordingPermission)
        // Invalid opt-in configuration must not query/capture the real desktop
        // or acquire the fake sensor. Native UI/capture adapters still compile.
        SettingsModel.shared.settings.systemEnhanceHingeAnimationBlur = .infinity
        SettingsModel.shared.settings.systemEnhanceHingeAnimationEnabled = true
        assert(manager.status == HingeAnimationPhase.invalidConfiguration.message)
        assert(!manager.needsScreenRecordingPermission)
        assert(LidAngleSensor.shared.acquisitions == 0)
        manager.stop()
        SettingsModel.shared.settings.systemEnhanceHingeAnimationEnabled = false
        assert(manager.status == HingeAnimationPhase.disabled.message)
        manager.start(); assert(manager.status == HingeAnimationPhase.disabled.message)
        manager.stop()
        print("Passed real hinge manager/native overlay-adapter compilation, disabled/invalid configuration and subscription teardown/startup with fake settings/sensor. No desktop capture, panel presentation or real hardware access.")
    }
}

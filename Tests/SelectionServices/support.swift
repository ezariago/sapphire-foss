struct Settings {
    var systemEnhanceServicesEnabled = false
    var systemEnhancePasteAsPlainStripLinks = false
    var systemEnhancePasteAsPlainStripEmojis = false
    var systemEnhancePasteAsPlainStripListMarkers = false
    var clipboardCleanURLCustomParams: [String] = []
}
@MainActor final class SettingsModel { static let shared = SettingsModel(); var current = Settings() }

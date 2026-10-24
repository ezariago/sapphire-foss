import Foundation
import Combine
struct Settings {
    var menuBarProfilesEnabled = false
    var menuBarProfiles: [MenuBarProfile] = []
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    @Published var settings = Settings()
}

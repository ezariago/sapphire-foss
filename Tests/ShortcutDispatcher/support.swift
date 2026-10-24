import AppKit
import Combine

struct DockLayout: Equatable { var id = UUID() }
struct Settings: Equatable {
    var planes: [Plane] = []
    var snapZoneShortcuts: [SnapZoneShortcut] = []
    var dockLayoutsEnabled = false
    var dockLayoutsPresets: [DockLayout] = []
    var disabledShortcutIDs = Set<String>()
    var customSnapLayouts: [SnapLayout] = []
    var defaultSnapLayout = LayoutTemplate.columns
    var externalEnabled = true
    var externalShortcut = KeyboardShortcut(key: "a", modifiers: .command)
    var unrelated = false
    func isShortcutEnabled(_ id: String) -> Bool { !disabledShortcutIDs.contains(id) }
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    @Published var settings = Settings()
}
enum ShortcutIdentifier {
    static func plane(_ id: UUID) -> String { "plane:\(id)" }
    static func snapZone(layoutID: UUID, zoneID: UUID) -> String { "zone:\(layoutID):\(zoneID)" }
}
enum PremiumGate {
    enum Feature { case snapZonesKeyboardShortcuts }
    static let accessChanges = PassthroughSubject<Void, Never>()
    static var allowed = true
    static func hasAccess(_ feature: Feature) -> Bool { allowed }
}
@MainActor final class KeyCodeTranslator {
    static let shared = KeyCodeTranslator()
    func keyCode(for key: String) -> UInt16? { ["a": UInt16(0), "b": UInt16(11)][key.lowercased()] }
}
final class ShortcutRecordingObserver {
    static var change: ((Bool) -> Void)?
    init(onChange: @escaping @Sendable (Bool) -> Void) { Self.change = onChange }
}
@MainActor final class AccessibilityTrustMonitor {
    static let shared = AccessibilityTrustMonitor()
    var suspend: (() -> Void)?
    var resume: (() -> Void)?
    func register<T: AnyObject>(name: String, owner: T, teardown: @escaping (T) -> Void, reinstall: @escaping (T) -> Void) {
        suspend = { [weak owner] in if let owner { teardown(owner) } }
        resume = { [weak owner] in if let owner { reinstall(owner) } }
    }
}
enum EventTapDecision { case pass, swallow }
enum EventTapPriority { static let shortcut = 200 }
enum SapphireSyntheticEventMarker { static let plainTextPaste: Int64 = 1234 }
// Inert transport: no OS hooks are installed and constructed events are never posted.
final class GlobalEventTap {
    struct Token { var id = UUID() }
    static let shared = GlobalEventTap()
    var reset: (() -> Void)?
    var body: ((CGEventType, CGEvent) -> EventTapDecision)?
    func register(name: String, mask: CGEventMask, priority: Int, reset: (() -> Void)? = nil, body: @escaping (CGEventType, CGEvent) -> EventTapDecision) -> Token? {
        self.body = body; self.reset = reset; return Token()
    }
    func unregister(_ token: Token) { body = nil }
    func emit(repeatKey: Bool = false, synthetic: Bool = false) -> EventTapDecision {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        event.flags = .maskCommand
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: SapphireSyntheticEventMarker.plainTextPaste) }
        return body?(.keyDown, event) ?? .pass
    }
}
@MainActor final class WindowArrangementManager {
    static let shared = WindowArrangementManager()
    var activated: [Plane] = []
    func activate(plane: Plane) { activated.append(plane) }
}
@MainActor enum SnappingManager {
    static var snapped: [UUID] = []
    static func snap(layoutID: UUID, zoneID: UUID) { snapped.append(zoneID) }
}

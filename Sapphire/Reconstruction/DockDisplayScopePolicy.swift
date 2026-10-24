#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

struct DockScopeDisplay: Equatable, Identifiable {
    let id: String // Runtime ID distinguishes simultaneously connected displays.
    let key: String // Persisted display identity, shared with other display settings.
    let aliases: [String]
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    var isValid: Bool {
        !id.isEmpty && !key.isEmpty && [frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height,
            visibleFrame.minX, visibleFrame.minY, visibleFrame.maxX, visibleFrame.maxY, visibleFrame.width, visibleFrame.height].allSatisfy(\.isFinite)
        && frame.width > 0 && frame.height > 0 && visibleFrame.width > 0 && visibleFrame.height > 0
        && frame.contains(visibleFrame)
    }
}

struct DockScopeConfiguration: Equatable {
    var locked = false
    var selectedDisplay: String?
    var previews = false
    var trigger = "hover"
    var layout = "grid"
    var delay = 0.25
    var enhanced = false
    var compact = false
    var otherSpaces = false
    var clicks = false
    var clickAction = "minimize"
    var allApps = true
    var selectedApps: [String] = []
    var excludedApps: [String] = []
}

struct DockScopeTicket: Equatable {
    let epoch: UInt64
    let displayID: String
    let point: CGPoint
}

struct DockDisplayScopeState {
    private(set) var epoch: UInt64 = 0
    private(set) var configuration = DockScopeConfiguration()
    private(set) var displays: [DockScopeDisplay] = []
    private(set) var suspended = true
    private var validTopology: Bool {
        !displays.isEmpty && displays.count <= 32 && displays.allSatisfy(\.isValid)
            && Set(displays.map(\.id)).count == displays.count
    }
    mutating func update(configuration: DockScopeConfiguration, displays: [DockScopeDisplay]) {
        let ordered = displays.sorted { $0.id < $1.id }
        guard self.configuration != configuration || self.displays != ordered else { return }
        self.configuration = configuration; self.displays = ordered; epoch &+= 1
    }
    mutating func setSuspended(_ value: Bool) {
        guard suspended != value else { return }; suspended = value; epoch &+= 1
    }
    var selected: DockScopeDisplay? {
        guard validTopology, let key = configuration.selectedDisplay, !key.isEmpty else { return nil }
        let exact = displays.filter { $0.key == key }
        if exact.count == 1 { return exact[0] }
        guard exact.isEmpty else { return nil }
        let legacy = displays.filter { $0.aliases.contains(key) }
        return legacy.count == 1 ? legacy[0] : nil
    }
    func ticket(at point: CGPoint) -> DockScopeTicket? {
        guard !suspended, validTopology, point.x.isFinite, point.y.isFinite else { return nil }
        let hit = displays.filter { $0.frame.contains(point) }
        guard hit.count == 1, !configuration.locked || hit[0].id == selected?.id else { return nil }
        return .init(epoch: epoch, displayID: hit[0].id, point: point)
    }
    func accepts(_ ticket: DockScopeTicket) -> Bool {
        guard epoch == ticket.epoch else { return false }
        return self.ticket(at: ticket.point)?.displayID == ticket.displayID
    }
    static func panelFrame(size: CGSize, near point: CGPoint, visibleFrame frame: CGRect) -> CGRect? {
        guard [size.width, size.height, point.x, point.y, frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height].allSatisfy(\.isFinite),
              size.width > 0, size.height > 0, frame.width > 0, frame.height > 0 else { return nil }
        let width = min(size.width, frame.width), height = min(size.height, frame.height)
        return CGRect(x: min(max(frame.minX, point.x - width / 2), frame.maxX - width),
                      y: min(max(frame.minY, point.y + 20), frame.maxY - height), width: width, height: height)
    }
}
#endif

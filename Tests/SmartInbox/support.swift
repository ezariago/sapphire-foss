import AppKit
import Combine
struct Settings { var smartInboxEnabled = true; var masterNotificationsEnabled = true; var parcelTrackingEnabled = true }
@MainActor final class SettingsModel { static let shared = SettingsModel(); @Published var settings = Settings() }
@MainActor final class PasteboardLane {
    static let shared = PasteboardLane()
    let board = NSPasteboard.withUniqueName()
    var pending: (() -> Void)?
    func write(_ body: @escaping (NSPasteboard) -> Bool, completion: (@MainActor (Int?) -> Void)?) {
        pending = { [self] in completion?(body(board) ? board.changeCount : nil) }
    }
    func flush() { let job = pending; pending = nil; job?() }
}
final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var value = 100.0
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Double) { lock.lock(); value = new; lock.unlock() }
}

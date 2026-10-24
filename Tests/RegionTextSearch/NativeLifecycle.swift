import AppKit
import Combine
import SwiftUI
struct KeyboardShortcut: Equatable { var key = "C" }
struct Settings {
    var regionTextSearchEnabled = false
    var circleToSearchEnabled = true
    var circleToSearchShortcut = KeyboardShortcut()
    var mediaToolsOCRLanguage = "en-US"
    var disabledShortcutIDs: Set<String> = []
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    @Published var settings = Settings()
    var current: Settings { settings }
}
enum ShortcutIdentifier { static let circleToSearch = "circleToSearch" }
@MainActor final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    struct ExternalShortcut { let identifier: String; let shortcut: KeyboardShortcut; let perform: @MainActor () -> Void }
    struct ExternalShortcutProvider { let shortcuts: @MainActor (Settings) -> [ExternalShortcut]; let reportUnavailable: @MainActor (Set<String>) -> Void }
    var provider: ExternalShortcutProvider?
    func registerExternalShortcutProvider(_ provider: ExternalShortcutProvider, named: String) { self.provider = provider }
}
enum NotchWidgetMode { case circleToSearch }
private final class FixturePaths: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [URL] = []
    func record(_ url: URL) { lock.withLock { paths.append(url.deletingLastPathComponent()) } }
    func allRemoved() -> Bool { lock.withLock { paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } } }
}
@main struct NativeLifecycle {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let manager = CircleToSearchManager.shared
        manager.selectRegion(); assert(!manager.session.busy)
        let provider = KeyboardShortcutManager.shared.provider!
        assert(provider.shortcuts(SettingsModel.shared.current).isEmpty)
        SettingsModel.shared.settings.regionTextSearchEnabled = true
        let bindings = provider.shortcuts(SettingsModel.shared.current)
        assert(bindings.count == 1)
        SettingsModel.shared.settings.regionTextSearchEnabled = false
        bindings[0].perform(); assert(!manager.session.busy)
        SettingsModel.shared.settings.regionTextSearchEnabled = true
        SettingsModel.shared.settings.circleToSearchShortcut.key = "X"
        bindings[0].perform(); assert(!manager.session.busy)
        SettingsModel.shared.settings.circleToSearchShortcut.key = "C"
        SettingsModel.shared.settings.disabledShortcutIDs.insert(ShortcutIdentifier.circleToSearch)
        bindings[0].perform(); assert(!manager.session.busy)
        provider.reportUnavailable([ShortcutIdentifier.circleToSearch]); assert(manager.shortcutUnavailable)
        manager.session.query = "secret"; manager.endResultsPresentation(); assert(manager.session.query.isEmpty)
        SettingsModel.shared.settings.regionTextSearchEnabled = false
        _ = CircleToSearchResultsView(navigationStack: .constant([.circleToSearch]))
        let image = NSImage(size: NSSize(width: 1000, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1000, height: 160)).fill()
        ("SAPPHIRE REGION SEARCH 2468" as NSString).draw(at: NSPoint(x: 35, y: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let outputs = FixturePaths()
        do {
            let text = try await RegionTextCapture.recognizeSelection(language: "en-US", select: { output in
                outputs.record(output)
                let permissions = try FileManager.default.attributesOfItem(atPath: output.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
                assert(permissions?.intValue == 0o700)
                try png.write(to: output)
            }, cancel: {})
            assert(text.contains("SAPPHIRE") && text.contains("2468"))
        } catch { fatalError("Generated image OCR failed: \(error)") }
        assert(outputs.allRemoved())
        do {
            _ = try await RegionTextCapture.recognizeSelection(language: "en-US", select: { output in
                outputs.record(output); try png.write(to: output); throw CancellationError()
            }, cancel: {})
            fatalError("Cancelled picker accepted")
        } catch { assert(outputs.allRemoved()) }
        print("Passed generated-image Vision recognition, private-directory permissions and success/failure cleanup; no screen captured.")
        print("Passed real native capture/manager/result-view compilation and disabled/stale shortcut guards with fake settings. No picker, desktop capture, clipboard or browser opened.")
    }
}

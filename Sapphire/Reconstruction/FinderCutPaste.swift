#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import ImageIO

private final class FinderInputConfiguration: @unchecked Sendable {
    let lock = NSLock()
    var enabled = false
    var rename = false
    var finderIsActive = false
    var swallowedKeys: Set<Int64> = []
}

@MainActor
final class FinderCutPasteManager {
    static let shared = FinderCutPasteManager()
    private let state = FinderInputConfiguration()
    private var tap: GlobalEventTap.Token?
    private var settings: AnyCancellable?
    private var observer: NSObjectProtocol?
    private var cutCount: Int?
    private var cutPaths: [String] = []
    private var captureGeneration = 0
    private init() {}
    func start() {
        guard settings == nil else { return }
        settings = SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] config in
            guard let self else { return }
            self.state.lock.withLock { self.state.enabled = config.clipboardFinderCutPasteEnabled; self.state.rename = config.clipboardFinderF2RenameEnabled }
            if !config.clipboardFinderCutPasteEnabled { self.cutCount = nil; self.cutPaths = []; self.captureGeneration += 1 }
        }
        updateActiveApp()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateActiveApp() }
        }
        let state = state
        tap = GlobalEventTap.shared.register(name: "FOSSFinderCutPaste", mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue), priority: EventTapPriority.transform) { [weak self] type, event in
            guard event.getIntegerValueField(.eventSourceUserData) != SapphireSyntheticEventMarker.plainTextPaste else { return .pass }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let action: Int = state.lock.withLock {
                if type == .keyUp { return state.swallowedKeys.remove(key) != nil ? -1 : 0 }
                guard state.enabled, state.finderIsActive, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return 0 }
                let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                let action = modifiers == .maskCommand && key == 7 ? 1 : modifiers == .maskCommand && key == 9 ? 2 : modifiers.isEmpty && key == 120 && state.rename ? 3 : 0
                if action != 0 { state.swallowedKeys.insert(key) }
                return action
            }
            guard action != 0 else { return .pass }
            if action > 0 {
                Task { @MainActor in
                    guard let self, SettingsModel.shared.current.clipboardFinderCutPasteEnabled,
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
                    if self.isEditingText() {
                        ClipboardSyntheticInput.key(action == 1 ? 7 : action == 2 ? 9 : 120, flags: action == 3 ? [] : .maskCommand)
                        return
                    }
                    switch action {
                    case 1: self.cut()
                    case 2: self.paste()
                    default: ClipboardSyntheticInput.key(36, flags: [])
                    }
                }
            }
            return .swallow
        }
    }
    private func updateActiveApp() {
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        state.lock.withLock { state.finderIsActive = active }
    }
    private func isEditingText() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              let focused: AXUIElement = SystemEnhanceWindowRegistry.attribute(AXUIElementCreateApplication(finder.processIdentifier), kAXFocusedUIElementAttribute) else { return true }
        let role: String = SystemEnhanceWindowRegistry.attribute(focused, kAXRoleAttribute) ?? ""
        return role.isEmpty || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }
    private func filePaths() -> [String] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).map(\.path)
    }
    private func cut() {
        cutCount = nil
        cutPaths = []
        captureGeneration += 1
        let generation = captureGeneration
        let before = NSPasteboard.general.changeCount
        ClipboardSyntheticInput.key(8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, generation == self.captureGeneration,
                  NSPasteboard.general.changeCount != before else { return }
            let files = self.filePaths()
            if !files.isEmpty { self.cutCount = NSPasteboard.general.changeCount; self.cutPaths = files }
        }
    }
    private func paste() {
        let matchesCut = cutCount == NSPasteboard.general.changeCount && !cutPaths.isEmpty && cutPaths == filePaths()
        if !matchesCut { cutCount = nil; cutPaths = [] }
        if matchesCut {
            cutCount = nil
            cutPaths = []
            ClipboardSyntheticInput.key(9, flags: [.maskCommand, .maskAlternate])
        } else if SettingsModel.shared.current.clipboardFinderPasteImagesAsPNG && pasteImage() {
            cutCount = nil
            cutPaths = []
        } else { ClipboardSyntheticInput.key(9) }
    }
    private func pasteImage() -> Bool {
        let pasteboard = NSPasteboard.general
        guard filePaths().isEmpty,
              let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000, width * height <= 40_000_000,
              let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        // The script is constant. No clipboard text or filenames become code.
        let script = NSAppleScript(source: "tell application \"Finder\" to get POSIX path of (insertion location as alias)")
        var error: NSDictionary?
        guard let directory = script?.executeAndReturnError(&error).stringValue, error == nil else { return false }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let output = folder.appendingPathComponent("Pasted Image \(UUID().uuidString.prefix(8)).png")
        do {
            try png.write(to: output, options: .withoutOverwriting)
            NSWorkspace.shared.activateFileViewerSelecting([output])
            return true
        } catch { return false }
    }
    func removeTap() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        settings = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observer = nil
        cutCount = nil; cutPaths = []; captureGeneration += 1
        state.lock.withLock { state.enabled = false; state.swallowedKeys.removeAll() }
    }
}
#endif

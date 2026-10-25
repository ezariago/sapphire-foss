#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import CoreServices

@MainActor
final class OCRScreenshotMonitor: ObservableObject {
    static let shared = OCRScreenshotMonitor()
    @Published private(set) var recognizedText = ""
    @Published private(set) var status: String?
    @Published private(set) var isProcessing = false
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var known: Set<URL> = []
    private var candidates: [URL: Date] = [:]
    private var generation = 0
    private var directory: URL?
    private var capture: Process?
    private init() {
        subscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.ocrScreenshotMonitorEnabled, shortcutEnabled: $0.mediaToolsOCRShortcutEnabled, shortcut: $0.mediaToolsOCRShortcut) }
            .removeDuplicates().receive(on: RunLoop.main).sink { [weak self] config in self?.configure(config) }
    }
    private struct Configuration: Equatable { let enabled: Bool; let shortcutEnabled: Bool; let shortcut: KeyboardShortcut }
    private func configure(_ config: Configuration) {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard settings.mediaToolsOCRShortcutEnabled else { return [] }
            return [.init(identifier: ShortcutIdentifier.ocrScreenshot, shortcut: settings.mediaToolsOCRShortcut, perform: { self?.captureRegion() })]
        }, reportUnavailable: { [weak self] unavailable in
            if !unavailable.isEmpty { self?.status = "The OCR shortcut conflicts with another shortcut." }
        }), named: "FOSSScreenshotOCR")
        if config.enabled && timer == nil {
            generation += 1
            directory = Self.screenshotDirectory()
            known = Set((try? FileManager.default.contentsOfDirectory(at: directory!, includingPropertiesForKeys: nil)) ?? [])
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        } else if !config.enabled {
            generation += 1
            timer?.invalidate(); timer = nil
            candidates.removeAll(); known.removeAll(); directory = nil
        }
    }
    private static func screenshotDirectory() -> URL {
        if let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }
    private func poll() {
        guard SettingsModel.shared.current.ocrScreenshotMonitorEnabled, let directory else { return }
        let currentDirectory = Self.screenshotDirectory()
        if directory != currentDirectory {
            self.directory = currentDirectory
            known = Set((try? FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: nil)) ?? [])
            candidates.removeAll()
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let current = Set(files)
        for file in current.subtracting(known).prefix(30) where MediaOptimizer.kind(for: file) == .image {
            candidates[file] = Date().addingTimeInterval(30)
        }
        known = current
        candidates = candidates.filter { current.contains($0.key) && $0.value > .now }
        guard !isProcessing, capture == nil else { return }
        for file in candidates.keys {
            // Only Spotlight-confirmed screenshots are read, not arbitrary images
            // arriving in Desktop/Downloads. Allow indexing time before retrying.
            if let item = MDItemCreate(kCFAllocatorDefault, file.path as CFString),
               (MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? NSNumber)?.boolValue == true {
                candidates.removeValue(forKey: file)
                process(file, removeAfter: false, monitoring: true)
                break
            }
        }
    }
    func captureRegion() {
        guard !isProcessing, capture == nil else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            status = "Allow Screen Recording in System Settings, then retry."
            return
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Sapphire-OCR-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-r", "-x", "-t", "png", output.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        capture = process
        recognizedText = ""
        status = "Select a screen region; press Escape to cancel."
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { try? FileManager.default.removeItem(at: output); return }
                self.capture = nil
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: output.path) {
                    self.process(output, removeAfter: true, monitoring: false)
                } else { self.status = "Screen selection cancelled."; try? FileManager.default.removeItem(at: output) }
            }
        }
        do { try process.run() }
        catch { capture = nil; status = error.localizedDescription }
    }
    private func process(_ url: URL, removeAfter: Bool, monitoring: Bool) {
        isProcessing = true
        let stamp = generation
        let language = SettingsModel.shared.current.mediaToolsOCRLanguage
        Task {
            defer { isProcessing = false; if removeAfter { try? FileManager.default.removeItem(at: url) } }
            let text: String
            do {
                text = try await Task.detached(priority: .utility) { try NativeMediaProcessor.recognizeText(in: url, language: language) }.value
            } catch {
                if monitoring && (stamp != generation || !SettingsModel.shared.current.ocrScreenshotMonitorEnabled) { return }
                recognizedText = ""
                status = error.localizedDescription
                return
            }
            if monitoring && (stamp != generation || !SettingsModel.shared.current.ocrScreenshotMonitorEnabled) { return }
            recognizedText = text
            status = recognizedText.isEmpty ? "No text recognized." : "Recognized \(recognizedText.count) characters locally."
            if !recognizedText.isEmpty && SettingsModel.shared.current.ocrScreenshotCopyTextAutomatically {
                ClipboardManager.shared.copyToClipboard(recognizedText)
            }
        }
    }
    func copyRecognizedText() {
        guard !recognizedText.isEmpty else { return }
        ClipboardManager.shared.copyToClipboard(recognizedText)
    }
    func clearRecognizedText() { recognizedText = ""; status = nil }
}
#endif

#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

@MainActor
final class MediaOptimizerManager: ObservableObject {
    static let shared = MediaOptimizerManager()
    @Published private(set) var status: String?
    @Published private(set) var isProcessing = false
    private init() {}
    func start() { ClipboardImageOptimizer.shared.start() }
    func stop() { ClipboardImageOptimizer.shared.stop() }
    func optimizeFile(_ url: URL) async -> Result<MediaOptimizeResult, MediaOptimizeError> {
        let config = SettingsModel.shared.current
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await NativeMediaProcessor.optimize(url, quality: config.mediaToolsImageQuality, maxDimension: config.mediaToolsMaxImageDimension)
            }.value
            return .success(result)
        } catch let error as MediaOptimizeError { return .failure(error) }
        catch { return .failure(.operationFailed(error.localizedDescription)) }
    }
    func recognizeText(in url: URL) async -> Result<String, MediaOptimizeError> {
        let language = SettingsModel.shared.current.mediaToolsOCRLanguage
        do {
            return .success(try await Task.detached(priority: .userInitiated) {
                try NativeMediaProcessor.recognizeText(in: url, language: language)
            }.value)
        } catch let error as MediaOptimizeError { return .failure(error) }
        catch { return .failure(.operationFailed(error.localizedDescription)) }
    }
    func chooseFiles(ocr: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        isProcessing = true
        Task {
            defer { isProcessing = false }
            for url in urls {
                if ocr {
                    switch await recognizeText(in: url) {
                    case .success(let text) where !text.isEmpty:
                        ClipboardManager.shared.copyToClipboard(text)
                        status = "Copied \(text.count) characters from \(url.lastPathComponent)."
                    case .success: status = "No readable text in \(url.lastPathComponent)."
                    case .failure(let error): status = error.localizedDescription
                    }
                } else {
                    switch await optimizeFile(url) {
                    case .success(let result): status = "Saved \(result.savedPercent)%: \(result.outputURL.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                    case .failure(let error): status = error.localizedDescription
                    }
                }
            }
        }
    }
}

struct MediaOptimizerSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var manager = MediaOptimizerManager.shared
    @ObservedObject private var screenshots = OCRScreenshotMonitor.shared
    @ObservedObject private var regionSearch = CircleToSearchManager.shared
    private var imageDimension: Binding<Double> {
        Binding(get: {
            let value = settings.settings.mediaToolsMaxImageDimension
            return value.isFinite ? min(8192, max(256, value)) : 2048
        }, set: { settings.settings.mediaToolsMaxImageDimension = $0.isFinite ? min(8192, max(256, $0)) : 2048 })
    }
    private var imageQuality: Binding<Double> {
        Binding(get: {
            let value = settings.settings.mediaToolsImageQuality
            return value.isFinite ? min(1, max(0.1, value)) : 0.75
        }, set: { settings.settings.mediaToolsImageQuality = $0.isFinite ? min(1, max(0.1, $0)) : 0.75 })
    }
    var body: some View {
        Form {
            Section("Media optimization") {
                Text("Creates a smaller copy beside the original. Images and PDFs use lossy screen-oriented compression; audio/video use native macOS export. The original stays unchanged, and outputs that are not smaller are discarded.")
                    .foregroundStyle(.secondary)
                Slider(value: imageQuality, in: 0.1...1) { Text("Image quality") }
                Stepper("Maximum image dimension: \(Int(imageDimension.wrappedValue)) px", value: imageDimension, in: 256...8192, step: 256)
                Toggle("Show media actions in File Shelf", isOn: $settings.settings.mediaToolsShowShelfActions)
                Button("Optimize files…") { manager.chooseFiles(ocr: false) }.disabled(manager.isProcessing)
            }
            Section("Clipboard images") {
                Toggle("Optimize newly copied images automatically", isOn: $settings.settings.mediaToolsAutoOptimizeClipboard)
                Text("Replaces a single PNG/TIFF-only clipboard item with a smaller PNG. It may reduce image dimensions (up to 4096 px); alpha is retained. File copies, rich content, marked items and images from ignored clipboard apps are skipped. Enabling does not process the current clipboard. Original image files stay unchanged.").foregroundStyle(.secondary)
                Text("Clipboard history and other apps may observe the original image before replacement. Use this only when automatic resizing is wanted.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Local text recognition") {
                Text("Uses Apple's Vision framework. Images and PDFs are processed on this Mac.").foregroundStyle(.secondary)
                TextField("Preferred recognition language", text: $settings.settings.mediaToolsOCRLanguage)
                Text("Uses the on-device fast recognizer for compatibility. It can miss small or complex text and supports fewer languages. Unsupported language choices report the languages available on this Mac.").font(.caption).foregroundStyle(.secondary)
                Button("Extract text from files…") { manager.chooseFiles(ocr: true) }.disabled(manager.isProcessing)
            }
            Section("Screen text search") {
                Toggle("Enable region text search", isOn: $settings.settings.regionTextSearchEnabled)
                Text("Select a region, review locally recognized text, then explicitly search Google in your browser. No image upload or reverse-image search. Screen Recording permission is required.").foregroundStyle(.secondary)
                Button("Select region for search…") { CircleToSearchManager.shared.selectRegion() }
                    .disabled(!settings.settings.regionTextSearchEnabled)
                Toggle("Enable region search shortcut", isOn: $settings.settings.circleToSearchEnabled)
                Text(KeyboardShortcutHelper.description(for: settings.settings.circleToSearchShortcut.modifiers) + settings.settings.circleToSearchShortcut.key)
                if regionSearch.shortcutUnavailable || settings.settings.disabledShortcutIDs.contains(ShortcutIdentifier.circleToSearch) {
                    Text("Region search shortcut is unavailable or disabled. Choose another combination in shortcut settings.").foregroundStyle(.orange)
                }
                Button("Record region search shortcut…") {
                    GlobalShortcutRecorder.shared.startRecording(identifier: ShortcutIdentifier.circleToSearch) { key, modifiers in
                        settings.settings.circleToSearchShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
                    }
                }
            }
            Section("Screenshot text") {
                Button("Select screen region…") { screenshots.captureRegion() }.disabled(screenshots.isProcessing)
                Toggle("Enable OCR screenshot shortcut", isOn: $settings.settings.mediaToolsOCRShortcutEnabled)
                Button("Record OCR shortcut…") {
                    GlobalShortcutRecorder.shared.startRecording(identifier: "ocrScreenshot") { key, modifiers in
                        settings.settings.mediaToolsOCRShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
                    }
                }
                Toggle("Monitor new screenshots", isOn: $settings.settings.ocrScreenshotMonitorEnabled)
                Text("Reads only new files confirmed by macOS as screenshots in your screenshot folder. Existing files are ignored. Recognized text remains in memory until you clear it or quit.").foregroundStyle(.secondary)
                Toggle("Copy recognized text automatically", isOn: $settings.settings.ocrScreenshotCopyTextAutomatically)
                Text("Clipboard sharing may send copied text to your paired phone.").font(.caption).foregroundStyle(.secondary)
                if let status = screenshots.status { Text(status) }
                if !screenshots.recognizedText.isEmpty {
                    ScrollView { Text(screenshots.recognizedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180)
                    HStack {
                        Button("Copy text") { screenshots.copyRecognizedText() }
                        Button("Clear text") { screenshots.clearRecognizedText() }
                    }
                }
            }
            if manager.isProcessing { ProgressView() }
            if let status = manager.status { Text(status).textSelection(.enabled) }
        }.formStyle(.grouped)
    }
}
#endif

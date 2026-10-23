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
    func start() {}
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
    func recognizeText(in url: URL) async -> String? {
        let language = SettingsModel.shared.current.mediaToolsOCRLanguage
        return try? await Task.detached(priority: .userInitiated) { try NativeMediaProcessor.recognizeText(in: url, language: language) }.value
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
                    if let text = await recognizeText(in: url), !text.isEmpty {
                        ClipboardManager.shared.copyToClipboard(text)
                        status = "Copied \(text.count) characters from \(url.lastPathComponent)."
                    } else { status = "No readable text in \(url.lastPathComponent)." }
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
    var body: some View {
        Form {
            Section("Media optimization") {
                Text("Creates a smaller copy beside the original. Images and PDFs use lossy screen-oriented compression; audio/video use native macOS export. The original stays unchanged, and outputs that are not smaller are discarded.")
                    .foregroundStyle(.secondary)
                Slider(value: $settings.settings.mediaToolsImageQuality, in: 0.1...1) { Text("Image quality") }
                Stepper("Maximum image dimension: \(Int(settings.settings.mediaToolsMaxImageDimension)) px", value: $settings.settings.mediaToolsMaxImageDimension, in: 256...8192, step: 256)
                Toggle("Show media actions in File Shelf", isOn: $settings.settings.mediaToolsShowShelfActions)
                Button("Optimize files…") { manager.chooseFiles(ocr: false) }.disabled(manager.isProcessing)
            }
            Section("Local text recognition") {
                Text("Uses Apple's Vision framework. Images and PDFs are processed on this Mac.").foregroundStyle(.secondary)
                TextField("Preferred recognition language", text: $settings.settings.mediaToolsOCRLanguage)
                Button("Extract text from files…") { manager.chooseFiles(ocr: true) }.disabled(manager.isProcessing)
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

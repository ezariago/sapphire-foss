#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DMGInstallerManager: ObservableObject {
    static let shared = DMGInstallerManager()
    @Published private(set) var currentTransferTask: FileTransferTask?
    @Published private(set) var isProcessing = false
    @Published private(set) var status: String?
    private var pending: [URL] = []
    private init() {}
    private static var types: [UTType] { ["com.apple.disk-image-udif", "public.disk-image"].compactMap(UTType.init) }
    static func isDefaultDMGHandler() -> Bool { types.allSatisfy { DefaultFileHandler.isThisApp(handlerURL: DefaultFileHandler.currentHandler(for: $0).url) } }
    static func setAsDefaultDMGHandler() {
        Task { @MainActor in
            let success = await DefaultFileHandler.claim(types)
            shared.status = success ? "Default disk-image handler updated." : "macOS did not change every disk-image association."
        }
    }
    static func shadowingCopy() -> URL? { DefaultFileHandler.shadowingCopy(for: types) }
    func reconcileDefaultHandlerIfNeeded() {
        guard SettingsModel.shared.current.dmgInstallerEnabled else { return }
        Task { await DefaultFileHandler.reclaimFromOtherCopies(Self.types) }
    }
    func handleOpenURLs(_ urls: [URL]) {
        let images = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "dmg" }
        guard !images.isEmpty else { return }
        guard SettingsModel.shared.current.dmgInstallerEnabled else { handOff(images); return }
        pending.append(contentsOf: images)
        guard !isProcessing else { return }
        isProcessing = true
        Task { @MainActor in
            defer { self.isProcessing = false; self.currentTransferTask = nil }
            while !self.pending.isEmpty {
                let url = self.pending.removeFirst()
                do { try await self.installImage(url) }
                catch is CancellationError { self.status = "Installation cancelled." }
                catch {
                    self.status = error.localizedDescription
                    let alert = NSAlert()
                    alert.messageText = "Could not install from \(url.lastPathComponent)"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Open in DiskImageMounter")
                    if alert.runModal() == .alertSecondButtonReturn { self.handOff([url]) }
                }
            }
        }
    }
    private func installImage(_ imageURL: URL) async throws {
        let config = SettingsModel.shared.current
        guard config.dmgInstallerEnabled else { throw CancellationError() }
        status = "Mounting \(imageURL.lastPathComponent)…"
        currentTransferTask = FileTransferTask(fileURL: imageURL, fileName: imageURL.lastPathComponent, destinationURL: config.dmgInstallerInstallLocation.url, sourceType: .dmgInstall)
        let mounted = try await Task.detached(priority: .userInitiated) { try DiskImageInstaller.mount(imageURL) }.value
        var installed: [DiskImageInstallResult] = []
        do {
            for source in mounted.applications {
                guard SettingsModel.shared.current.dmgInstallerEnabled else { throw CancellationError() }
                let identity = try await Task.detached { try AppSecurityValidator.identity(at: source) }.value
                let destination = config.dmgInstallerInstallLocation.url.appendingPathComponent(source.lastPathComponent)
                let replacing = FileManager.default.fileExists(atPath: destination.path)
                if replacing && !config.dmgInstallerReplaceNewerVersions {
                    let old = Bundle(url: destination)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let new = Bundle(url: source)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    if old.compare(new, options: .numeric) == .orderedDescending {
                        throw DiskImageInstallError.commandFailed("The installed version is newer; replacement is disabled in Settings.")
                    }
                }
                if !replacing || !config.dmgInstallerReplaceWithoutPrompting {
                    let alert = NSAlert()
                    alert.messageText = replacing ? "Replace \(source.lastPathComponent)?" : "Install \(source.lastPathComponent)?"
                    alert.informativeText = "Destination: \(destination.path)\nSigner team: \(identity.teamIdentifier ?? "Local/ad-hoc signature")\n" + (replacing ? "The installed app must be quit and signed by the same publisher. A backup will be retained." : "macOS will assess the app when you open it.")
                    alert.addButton(withTitle: replacing ? "Replace" : "Install")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
                }
                status = "Installing \(source.lastPathComponent)…"
                let result = try await Task.detached(priority: .userInitiated) {
                    try DiskImageInstaller.install(source, to: config.dmgInstallerInstallLocation.url, replace: replacing, quarantineSource: imageURL)
                }.value
                installed.append(result)
            }
            try await Task.detached { try DiskImageInstaller.unmount(mounted) }.value
        } catch {
            _ = try? await Task.detached { try DiskImageInstaller.unmount(mounted) }.value
            if !installed.isEmpty {
                let names = installed.map { $0.application.lastPathComponent }.joined(separator: ", ")
                throw DiskImageInstallError.commandFailed("Installed \(names) before this operation stopped: \(error.localizedDescription). Completed installations and their backups are retained.")
            }
            throw error
        }
        currentTransferTask?.isComplete = true
        currentTransferTask?.status = .finished
        let backups = installed.compactMap(\.backup)
        status = "Installed \(installed.count) application(s)." + (backups.isEmpty ? "" : " Previous versions are retained beside the app as hidden .Sapphire-backup files.")
        if config.dmgInstallerTrashAfterInstall { _ = try? FileManager.default.trashItem(at: imageURL, resultingItemURL: nil) }
        for result in installed {
            switch config.dmgInstallerPostInstallAction {
            case .open: NSWorkspace.shared.open(result.application)
            case .revealInFinder: NSWorkspace.shared.activateFileViewerSelecting([result.application])
            case .none: break
            }
        }
        try? await Task.sleep(for: .seconds(2))
    }
    private func handOff(_ urls: [URL]) {
        if let mounter = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.DiskImageMounter") {
            NSWorkspace.shared.open(urls, withApplicationAt: mounter, configuration: NSWorkspace.OpenConfiguration())
        } else { status = "DiskImageMounter is unavailable. Open the image manually in Finder." }
    }
}

struct ArchivesAndDMGInstallerSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var installer = DMGInstallerManager.shared
    @State private var archiveStatus: String?
    var body: some View {
        Form {
            Section("Archive extraction") {
                Toggle("Enable archive extractor", isOn: $settings.settings.archiveExtractorEnabled)
                Picker("Extraction mode", selection: $settings.settings.archiveExtractionMode) {
                    ForEach(ArchiveExtractionMode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("After extraction", selection: $settings.settings.archivePostExtractAction) {
                    ForEach(ArchivePostExtractAction.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Ask for archive passwords", isOn: $settings.settings.archivePromptForPasswords)
                Toggle("Trash archive after extraction", isOn: $settings.settings.archiveDeleteAfterExtract)
                Button("Use Sapphire to open supported archives") {
                    Task { archiveStatus = await ArchiveExtractor.setAsDefaultArchiveHandler() ? "Archive defaults updated." : "Some file associations could not be changed." }
                }
                if let archiveStatus { Text(archiveStatus).foregroundStyle(.secondary) }
            }
            Section("Disk image installer") {
                Toggle("Enable DMG installer", isOn: $settings.settings.dmgInstallerEnabled)
                Text("Mounts images read-only, validates app signatures and stages copies before installing. Existing apps require the installed publisher's signature and are backed up. Package installers and unsigned apps can be opened with DiskImageMounter instead.")
                    .foregroundStyle(.secondary)
                Picker("Install location", selection: $settings.settings.dmgInstallerInstallLocation) {
                    ForEach(DMGInstallLocation.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("After installation", selection: $settings.settings.dmgInstallerPostInstallAction) {
                    ForEach(DMGPostInstallAction.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Allow replacing a newer installed version", isOn: $settings.settings.dmgInstallerReplaceNewerVersions)
                Toggle("Replace without confirmation", isOn: $settings.settings.dmgInstallerReplaceWithoutPrompting)
                Toggle("Trash DMG after successful installation", isOn: $settings.settings.dmgInstallerTrashAfterInstall)
                Button("Open a DMG…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "dmg") ?? .diskImage]
                    guard panel.runModal() == .OK else { return }
                    installer.handleOpenURLs(panel.urls)
                }.disabled(!settings.settings.dmgInstallerEnabled || installer.isProcessing)
                Button("Use Sapphire to open disk images") { DMGInstallerManager.setAsDefaultDMGHandler() }
                if installer.isProcessing { ProgressView() }
                if let status = installer.status { Text(status).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
    }
}
#endif

import AppKit
import SwiftUI

@main struct StorageFixture {
    @MainActor static func wait(_ condition: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline { try! await Task.sleep(for: .milliseconds(25)) }
        assert(condition(), "Storage fixture deadline exceeded")
    }
    @MainActor static func main() async throws {
        verifyStorageSpaceMap()
        let renderMap = CommandLine.arguments.contains("--render-space-map")
        let renderHistory = CommandLine.arguments.contains("--render-history")
        let renderReview = CommandLine.arguments.contains("--render-review")
        let render = renderMap || renderHistory || renderReview || CommandLine.arguments.contains("--render")
        if render {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("dev.sapphire.storage-fixture.") else { fatalError("Fixture requires isolated defaults domain") }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let scope = root.appendingPathComponent("Scope", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: scope, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let alpha = scope.appendingPathComponent("alpha.bin")
        let beta = scope.appendingPathComponent("beta.bin")
        let external = outside.appendingPathComponent("outside.bin")
        let data = Data(repeating: 42, count: 1_100_000)
        try data.write(to: alpha); try data.write(to: beta); try data.write(to: external)
        try fm.createSymbolicLink(at: scope.appendingPathComponent("outside-link"), withDestinationURL: external)
        let model = StorageViewModel()
        model.open(StorageEntry(url: scope, size: 0, isDirectory: true))
        await wait { !model.isLoading }
        assert(model.scanState == .completed)
        let initialHistory = model.currentScopeScanHistory
        assert(!initialHistory.isEmpty && initialHistory.allSatisfy { $0.deepScanEnabled == false && $0.scopeIdentifier != nil && $0.spaceFreed == 0 })
        let initialScope = initialHistory.last!.scopeIdentifier
        model.open(StorageEntry(url: outside, size: 0, isDirectory: true))
        await wait { !model.isLoading }
        assert(!model.currentScopeScanHistory.isEmpty && model.currentScopeScanHistory.allSatisfy { $0.scopeIdentifier != initialScope })
        model.open(StorageEntry(url: scope, size: 0, isDirectory: true))
        await wait { !model.isLoading }
        assert(model.currentScopeScanHistory.allSatisfy { $0.scopeIdentifier == initialScope && $0.deepScanEnabled == false })
        assert(model.entries.contains { $0.name == "alpha.bin" && $0.logicalSize == 1_100_000 })
        assert(model.entries.contains { $0.name == "outside-link" && $0.isSymbolicLink })
        model.filterText = "alpha"
        assert(model.filteredAndSortedEntries.count == 1)
        model.filterText = ""; model.sortBy = .name
        assert(model.filteredAndSortedEntries.map(\.name) == model.filteredAndSortedEntries.map(\.name).sorted())
        model.deepScanEnabled = true; model.rescan()
        await wait { !model.isLoading }
        assert(model.scanState == .completed)
        assert(!model.currentScopeScanHistory.isEmpty && model.currentScopeScanHistory.allSatisfy { $0.scopeIdentifier == initialScope && $0.deepScanEnabled == true && $0.spaceFreed == 0 })
        assert(model.recommendations.allSatisfy { ($0.category == .duplicates || !$0.entries.isEmpty) && $0.potentialSpaceFreed >= 0 })
        assert(model.duplicateGroups.contains { Set($0.entries.map(\.name)) == Set(["alpha.bin", "beta.bin"]) })
        // Capacity is delivered by a separate detached task, not the scan task.
        await wait { model.total > 0 || model.capacityError != nil }
        assert(model.total > 0 && model.available >= 0 && model.availableForImportantUsage <= model.total)
        let record = model.entries.first { $0.url == alpha }!
        model.requestRemoval(StorageEntry(url: URL(fileURLWithPath: "/"), size: 0, isDirectory: true))
        assert(!model.confirmingRemoval && !model.removalIssues.isEmpty)
        model.requestRemoval(StorageEntry(url: external, size: 1_100_000, isDirectory: false))
        assert(!model.confirmingRemoval && !model.removalIssues.isEmpty)
        model.requestRemoval(model.entries.first { $0.isSymbolicLink }!)
        assert(!model.confirmingRemoval && !model.removalIssues.isEmpty)
        model.requestRemoval(record)
        assert(model.confirmingRemoval && model.pendingRemovalEntries.count == 1)
        model.cancelRemovalRequest()
        assert(!model.confirmingRemoval && model.pendingRemovalEntries.isEmpty && fm.fileExists(atPath: alpha.path))
        model.requestRemoval(record)
        try Data(repeating: 9, count: 1_100_001).write(to: alpha)
        model.removeConfirmed()
        await wait { !model.isRemoving }
        assert(model.lastRemovalResult?.removed.isEmpty == true && !model.removalIssues.isEmpty)
        assert(fm.fileExists(atPath: alpha.path) && fm.fileExists(atPath: external.path))
        model.rescan(); model.cancelScan()
        try await Task.sleep(for: .milliseconds(150))
        assert(!model.isLoading && model.scanState == .cancelled)
        if render {
            // Match the real scroll container and attach a temporary window wholly
            // outside every display. Capture only this synthetic fixture view.
            let host = NSHostingView(rootView: ScrollView { StorageWorkspaceView(model: model, initialResults: renderMap ? .spaceMap : (renderHistory ? .history : (renderReview ? .recommendations : .files))).padding(20) }.background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
            let minX = NSScreen.screens.map { $0.frame.minX }.min() ?? 0
            let window = NSWindow(contentRect: NSRect(x: minX - 2000, y: 0, width: 850, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Fixture bitmap unavailable") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Fixture PNG unavailable") }
            let target = URL(fileURLWithPath: CommandLine.arguments[2])
            let name = renderMap ? "space-map.png" : (renderHistory ? "history.png" : (renderReview ? "review.png" : target.lastPathComponent))
            try png.write(to: target.deletingLastPathComponent().appendingPathComponent(name))
            window.orderOut(nil)
        }
        print("Passed real isolated storage scans, duplicate hashing, filtering/sorting, capacity bounds, protected/out-of-scope/symlink rejection, cancel and stale-removal refusal; no files were trashed and no user data was scanned.")
    }
}

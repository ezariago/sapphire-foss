#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI

private struct StorageCapacityCard: View {
    @ObservedObject var model: StorageViewModel
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            Label(model.total > 0 ? model.volumeName : "Storage", systemImage: "internaldrive.fill").font(.headline)
            if model.total > 0 {
                Text(model.availableForImportantUsage.formatted(.byteCount(style: .file)) + " available")
                    .font(compact ? .title3.bold() : .title2.bold()).monospacedDigit()
                ProgressView(value: min(1, max(0, Double(model.used) / Double(model.total))))
                    .tint(.cyan)
                    .accessibilityLabel("Used storage excluding purgeable space")
                Text("of " + model.total.formatted(.byteCount(style: .file)) + " · includes purgeable space")
                    .font(.caption).foregroundStyle(.secondary)
                if !compact {
                    LabeledContent("Free now", value: model.available.formatted(.byteCount(style: .file)))
                    LabeledContent("Purgeable estimate", value: model.purgeableBytes.formatted(.byteCount(style: .file)))
                }
            } else if let error = model.capacityError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("Reading capacity…")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StorageWidgetView: View {
    @StateObject private var model = StorageViewModel()
    var body: some View {
        StorageCapacityCard(model: model, compact: true)
            .frame(width: 225, alignment: .leading)
            .task {
                while !Task.isCancelled {
                    model.refreshCapacity()
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                }
            }
    }
}

struct StorageDetailView: View {
    @StateObject private var model = StorageViewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StorageCapacityCard(model: model)
            Text("Available space includes space macOS estimates it can purge. Shared APFS volumes and snapshots can affect these figures.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Refresh") { model.refreshCapacity() }
                Button("Show disk in Finder") { model.reveal(model.volumeURL) }
            }
        }.padding(18).frame(width: 360)
            .task {
                while !Task.isCancelled {
                    model.refreshCapacity()
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                }
            }
    }
}

struct StorageWorkspaceView: View {
    @ObservedObject var model: StorageViewModel
    enum Results: String, CaseIterable { case files = "Files", spaceMap = "Space Map", tree = "Tree", pie = "Pie", categories = "Categories", duplicates = "Duplicates", recommendations = "Review", history = "History" }
    @State private var results: Results
    @State private var selectedMapURL: URL?
    @State private var selectedTreeURL: URL?
    init(model: StorageViewModel, initialResults: Results = .files) {
        self.model = model
        _results = State(initialValue: initialResults)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StorageCapacityCard(model: model)
                .padding().background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Choose folder…") { chooseFolder() }.disabled(model.isRemoving)
                Button("Root disk") { navigate(URL(fileURLWithPath: "/")) }.disabled(model.isRemoving || model.currentURL.path == "/")
                Spacer()
                if model.isLoading { Button("Cancel scan") { model.cancelScan() } }
                else { Button("Scan folder") { model.rescan() }.disabled(model.isRemoving) }
            }
            Text(model.currentURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Toggle("Deep scan (includes duplicate hashing)", isOn: $model.deepScanEnabled).disabled(model.isLoading || model.isRemoving)
            Text("Choose a folder and scan to inspect its contents. Deep scans can take longer. Capacity refreshes do not scan files.")
                .font(.caption).foregroundStyle(.secondary)
            if model.isLoading {
                ProgressView(value: model.indexingProgress)
                Text(model.indexingLabel).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(scanStatus).font(.caption).foregroundStyle(.secondary)
            }
            if let metrics = model.scanMetrics, metrics.isTrimmed {
                Text("The scan reached its result limit. These results do not include every item.").foregroundStyle(.orange).font(.caption)
            }
            if results == .files || results == .spaceMap || results == .tree {
                HStack {
                    TextField("Search scan results", text: $model.filterText).textFieldStyle(.roundedBorder)
                    if results == .files {
                        Picker("Sort", selection: $model.sortBy) {
                            ForEach(StorageViewModel.SortOption.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                        }.frame(maxWidth: 230)
                    }
                }
            } else if results == .duplicates {
                TextField("Search duplicate paths", text: $model.filterText).textFieldStyle(.roundedBorder)
            }
            Picker("Results", selection: $results) {
                ForEach(Results.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if results == .files {
                if let category = model.categoryFilter {
                    HStack { Text("Showing \(category.rawValue)"); Button("Clear category filter") { model.categoryFilter = nil } }.font(.caption)
                }
                if visibleEntries.isEmpty { Text("No matching entries in this scan.").foregroundStyle(.secondary) }
                LazyVStack(spacing: 0) {
                    ForEach(visibleEntries) { entry in entryRow(entry, showPath: model.categoryFilter != nil && model.deepScanEnabled) }
                }
            } else if results == .spaceMap {
                if let category = model.categoryFilter {
                    HStack { Text("Direct entries in \(category.rawValue)"); Button("Clear category filter") { model.categoryFilter = nil } }.font(.caption)
                }
                let snapshot = model.spaceMapSnapshot(maximumItems: 48)
                StorageSpaceMapView(snapshot: snapshot, selectedURL: selectedMapURL) { selectedMapURL = $0.url }
                if let selected = snapshot.items.compactMap(\.entry).first(where: { $0.url == selectedMapURL }) {
                    entryRow(selected, showPath: true)
                } else {
                    Text("Select a tile to inspect, open its folder or reveal it in Finder.").font(.caption).foregroundStyle(.secondary)
                }
            } else if results == .tree {
                let snapshot = StorageRetainedTreeSnapshot.make(root: model.currentURL, direct: model.entries, insights: model.insightEntries,
                    search: model.filterText, category: model.categoryFilter)
                if let category = model.categoryFilter {
                    HStack { Text("Retained matches for \(category.rawValue)"); Button("Clear category filter") { model.categoryFilter = nil } }.font(.caption)
                }
                StorageRetainedTreeView(snapshot: snapshot) { selectedTreeURL = StorageRetainedTreeSnapshot.key(for: $0.url) }
                if let url = selectedTreeURL, let entry = snapshot.records[url] { entryRow(entry, showPath: true) }
                else { Text("Select a retained record to use the existing inspection and reviewed actions.").font(.caption).foregroundStyle(.secondary) }
            } else if results == .pie {
                StoragePieView(snapshot: .make(model.totalCategorySize)) { category in
                    model.categoryFilter = category; results = .files
                }
            } else if results == .history {
                StorageScanHistoryView(history: model.currentScopeScanHistory)
            } else if results == .recommendations {
                recommendationResults
            } else if results == .categories {
                ForEach(StorageCategory.allCases, id: \.rawValue) { category in
                    Button {
                        model.categoryFilter = category; results = .files
                    } label: {
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                            Spacer()
                            Text((model.totalCategorySize[category] ?? 0).formatted(.byteCount(style: .file))).monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 7)
                    }.buttonStyle(.plain)
                }
                Text("Category totals describe the scanned scope. Filters such as large, old and duplicate files can overlap.").font(.caption).foregroundStyle(.secondary)
            } else {
                if !model.deepScanEnabled { Text("Enable Deep scan, then scan to find duplicate groups.").foregroundStyle(.secondary) }
                else if visibleDuplicateGroups.isEmpty { Text("No matching duplicate groups in this scan.").foregroundStyle(.secondary) }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(visibleDuplicateGroups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(group.entries.count) copies · \(group.logicalFileSize.formatted(.byteCount(style: .file))) each").font(.headline)
                            Text("Potential duplicate bytes: " + group.reclaimableBytes.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary)
                            ForEach(duplicateEntries(group).prefix(50)) { entry in entryRow(entry, showPath: true) }
                            if duplicateEntries(group).count > 50 { Text("Showing the first 50 matching paths in this group.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if !model.scanErrors.isEmpty {
                DisclosureGroup("Scan issues (\(model.scanErrors.count))") {
                    ForEach(model.scanErrors.prefix(100)) { issue in
                        Text((issue.url?.path).map { $0 + ": " + issue.message } ?? issue.message)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if model.scanErrors.count > 100 { Text("Showing the first 100 issues.").font(.caption) }
                }
            }
            if model.isRemoving { ProgressView("Moving reviewed items to Trash…") }
            if let removal = model.lastRemovalResult, !removal.removed.isEmpty {
                Text("Moved \(removal.removed.count) item(s) to Trash. Disk space is not reclaimed until Trash is emptied in Finder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.removalIssues.isEmpty {
                DisclosureGroup("Removal issues (\(model.removalIssues.count))") {
                    ForEach(model.removalIssues.prefix(100)) { issue in
                        Text((issue.url?.path).map { $0 + ": " + issue.message } ?? issue.message)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if model.removalIssues.count > 100 { Text("Showing the first 100 issues.").font(.caption) }
                }
            }
        }
    }
    private var recommendationResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review scan candidates").font(.headline)
            Text("Candidates and byte estimates can overlap. Inspect each item before moving it to Trash. Nothing is removed automatically, and no duplicate copy is chosen for you.")
                .font(.caption).foregroundStyle(.secondary)
            if model.recommendations.isEmpty { Text("No cleanup candidates in this scan.").foregroundStyle(.secondary) }
            ForEach(model.recommendations) { recommendation in
                DisclosureGroup {
                    if recommendation.category == .duplicates {
                        Button("Review duplicate groups") { results = .duplicates }
                        Text("Choose copies individually after inspecting the group; no file is selected automatically.").font(.caption).foregroundStyle(.secondary)
                    } else if recommendation.entries.isEmpty {
                        Text("No individual candidate entries retained in this scan snapshot.").font(.caption).foregroundStyle(.secondary)
                    }
                    if recommendation.category == .trash {
                        Text("Already in Trash. Review in Finder; Sapphire does not empty Trash.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(recommendation.entries.prefix(50)) { entry in
                        entryRow(entry, showPath: true, allowTrash: recommendation.category != .trash)
                    }
                    if recommendation.entries.count > 50 {
                        Text("Showing 50 of \(recommendation.entries.count) candidates. Use Categories or Files to inspect more.").font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Label(recommendation.category.rawValue, systemImage: recommendation.category.icon)
                        Spacer()
                        Text("Candidate bytes: " + max(0, recommendation.potentialSpaceFreed).formatted(.byteCount(style: .file))).font(.caption).monospacedDigit()
                    }
                }
            }
        }
    }
    private var visibleEntries: [StorageEntry] {
        model.categoryFilter != nil && model.deepScanEnabled ? model.filteredAndSortedInsightEntries : model.filteredAndSortedEntries
    }
    private var visibleDuplicateGroups: [StorageDuplicateGroup] {
        model.duplicateGroups.filter { !duplicateEntries($0).isEmpty }
    }
    private func duplicateEntries(_ group: StorageDuplicateGroup) -> [StorageEntry] {
        guard !model.filterText.isEmpty else { return group.entries }
        return group.entries.filter { $0.url.path.localizedCaseInsensitiveContains(model.filterText) }
    }
    private var scanStatus: String {
        switch model.scanState {
        case .idle: "Ready to scan"
        case .loadingCache: "Loading recent scan…"
        case .scanning, .hashingDuplicates: model.indexingLabel
        case .completed: "Scan complete · \(model.entries.count) entries"
        case .cancelled: "Scan cancelled; results may be incomplete"
        case .failed(let message): "Scan failed: \(message)"
        }
    }
    private func navigate(_ url: URL) {
        model.filterText = ""; model.categoryFilter = nil
        model.open(StorageEntry(url: url, size: 0, isDirectory: true))
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = model.currentURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        navigate(url)
    }
    private func entryRow(_ entry: StorageEntry, showPath: Bool = false, allowTrash: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.isSymbolicLink ? "link" : (entry.isDirectory ? "folder" : "doc"))
                .foregroundStyle(entry.category.color).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).lineLimit(1)
                if showPath { Text(entry.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if entry.isSystemProtected { Text("Inspection only").font(.caption).foregroundStyle(.secondary) }
                if let warning = entry.scanWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Text(entry.size.formatted(.byteCount(style: .file))).monospacedDigit()
            if entry.isDirectory && !entry.isPackage && !entry.isSymbolicLink {
                Button("Open folder") { navigate(entry.url) }.disabled(model.isRemoving)
            }
            Button("Reveal") { model.reveal(entry) }
            Button("Trash…", role: .destructive) { model.requestRemoval(entry) }
                .disabled(!allowTrash || model.isRemoving || model.isLoading || entry.isSystemProtected)
        }.padding(.vertical, 8)
    }
}
#endif

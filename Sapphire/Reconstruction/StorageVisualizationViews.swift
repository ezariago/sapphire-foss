#if !SAPPHIRE_FULL_BUILD
import SwiftUI

private struct StoragePieSlice: Shape {
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0, radius.isFinite, start.isFinite, end.isFinite, end > start else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY), inner = radius * 0.57
        let first = Angle.radians(start * 2 * .pi - .pi / 2), last = Angle.radians(end * 2 * .pi - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: first, endAngle: last, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + inner * cos(last.radians), y: center.y + inner * sin(last.radians)))
        path.addArc(center: center, radius: inner, startAngle: last, endAngle: first, clockwise: true)
        path.closeSubpath()
        return path
    }
}
struct StoragePieView: View {
    let snapshot: StoragePieSnapshot
    let select: (StorageCategory) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.items.isEmpty {
                ContentUnavailableView("No category measurements", systemImage: "chart.pie", description: Text("Scan a folder to measure allocated bytes in primary categories."))
            } else {
                HStack(alignment: .center, spacing: 24) {
                    ZStack {
                        ForEach(snapshot.items) { item in
                            let slice = StoragePieSlice(start: item.start, end: item.end)
                            Button { select(item.category) } label: { slice.fill(item.category.color) }
                                .buttonStyle(.plain).contentShape(slice)
                                .accessibilityLabel(item.category.rawValue + ", " + item.bytes.formatted(.byteCount(style: .file)))
                                .help(item.category.rawValue + " · " + item.fraction.formatted(.percent.precision(.fractionLength(1))))
                        }
                        VStack {
                            Text("Accounted").font(.caption).foregroundStyle(.secondary)
                            Text(snapshot.displayTotal.formatted(.byteCount(style: .file))).font(.headline).monospacedDigit()
                        }.allowsHitTesting(false)
                    }.frame(width: 280, height: 280)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(snapshot.items) { item in
                            Button { select(item.category) } label: {
                                HStack {
                                    Circle().fill(item.category.color).frame(width: 9, height: 9)
                                    Text(item.category.rawValue)
                                    Spacer()
                                    Text(item.bytes.formatted(.byteCount(style: .file))).monospacedDigit()
                                    Text(item.fraction.formatted(.percent.precision(.fractionLength(1)))).foregroundStyle(.secondary).frame(minWidth: 48, alignment: .trailing)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Primary allocated-byte categories from the scanned scope, not whole-disk capacity or recoverable space. Cleanup filters can overlap; these chart values use the scanner’s primary accounting categories. Select a segment or legend to inspect its category filter.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct StorageRetainedTreeView: View {
    let snapshot: StorageRetainedTreeSnapshot
    let select: (StorageEntry) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Retained scan records").font(.headline)
            Text("\(snapshot.retainedRecordCount) matching records · \(snapshot.contextFolderCount) inferred context folders. This is a bounded hierarchy of direct entries and retained insights, not a complete recursive file inventory. Parent rows provide context. Expanding rows reads no new files. Open a folder through its inspection row and scan it to inspect more.")
                .font(.caption).foregroundStyle(.secondary)
            if snapshot.roots.isEmpty { Text("No matching retained paths.").foregroundStyle(.secondary) }
            OutlineGroup(snapshot.roots, children: \.children) { node in
                HStack {
                    Image(systemName: node.entry?.isDirectory == false ? "doc" : "folder").foregroundStyle(.secondary)
                    if let entry = node.entry {
                        Button { select(entry) } label: { Text(node.name).lineLimit(1) }.buttonStyle(.plain)
                        if node.isContext { Text("Context").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        Text(entry.size > 0 ? entry.size.formatted(.byteCount(style: .file)) : "Zero / unknown").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(node.name).lineLimit(1)
                        Spacer()
                        Text("Context folder").font(.caption).foregroundStyle(.secondary)
                    }
                }.help(node.url.path).padding(.vertical, 3)
            }
            if snapshot.omittedRecordCount > 0 { Text("\(snapshot.omittedRecordCount) matching records were omitted by depth/node/record limits or invalid ancestry. Narrow the search to inspect a smaller subset.").font(.caption).foregroundStyle(.orange) }
            Text("Folder estimates can include descendant bytes. Do not add tree rows together. Inferred context folders have no fabricated byte total or filesystem action.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif

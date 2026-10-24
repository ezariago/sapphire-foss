#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct StorageSpaceMapView: View {
    let snapshot: StorageSpaceMapSnapshot
    let selectedURL: URL?
    let select: (StorageEntry) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.items.isEmpty {
                ContentUnavailableView("No measured sizes", systemImage: "square.grid.2x2", description: Text("No positive allocated sizes in these filtered results. Clear filters or scan a folder."))
            } else {
                GeometryReader { geometry in
                    let rects = snapshot.rectangles
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(snapshot.items.enumerated()), id: \.element.id) { index, item in
                            let rect = rects[index]
                            let width = max(0, rect.width * geometry.size.width)
                            let height = max(0, rect.height * geometry.size.height)
                            Group {
                                if let entry = item.entry {
                                    Button { select(entry) } label: { tile(item, width: width, height: height) }.buttonStyle(.plain)
                                        .accessibilityLabel(entry.name + ", " + item.bytes.formatted(.byteCount(style: .file)))
                                        .help(entry.url.path + " · " + item.bytes.formatted(.byteCount(style: .file)))
                                } else {
                                    tile(item, width: width, height: height)
                                        .help("\(item.count) smaller entries grouped together")
                                }
                            }
                            .frame(width: width, height: height)
                            .position(x: (rect.midX * geometry.size.width), y: (rect.midY * geometry.size.height))
                        }
                    }
                }.frame(height: 300).clipped()
            }
            Text("Area represents allocated bytes among these filtered direct entries, including a grouped remainder. It does not represent whole-disk usage, logical size or reclaimable bytes.")
                .font(.caption).foregroundStyle(.secondary)
            if !snapshot.isDeepScan {
                Text("Use a deep scan for measured directory totals. Shallow scans may show only files and directory metadata.").font(.caption).foregroundStyle(.secondary)
            }
            if snapshot.omittedZeroSizeCount > 0 {
                Text("\(snapshot.omittedZeroSizeCount) zero/unknown-size entries have no area; inspect them in Files.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func tile(_ item: StorageSpaceMapSnapshot.Item, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            (item.entry?.category.color ?? .gray).opacity(0.8)
            if width >= 70, height >= 35 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.caption.weight(.semibold)).lineLimit(2)
                    if height >= 55 { Text(item.bytes.formatted(.byteCount(style: .file))).font(.caption2).lineLimit(1) }
                }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(Rectangle().stroke(item.entry?.url == selectedURL && selectedURL != nil ? Color.white : Color.black.opacity(0.3), lineWidth: item.entry?.url == selectedURL && selectedURL != nil ? 3 : 1))
        .clipped()
    }
}
#endif

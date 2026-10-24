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
                            cell(item, rect: rects[index], size: geometry.size)
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
    private func cell(_ item: StorageSpaceMapSnapshot.Item, rect: CGRect, size: CGSize) -> some View {
        let width: CGFloat = max(0, rect.width * size.width)
        let height: CGFloat = max(0, rect.height * size.height)
        return tileControl(item, width: width, height: height)
            .frame(width: width, height: height)
            .position(x: rect.midX * size.width, y: rect.midY * size.height)
    }
    @ViewBuilder private func tileControl(_ item: StorageSpaceMapSnapshot.Item, width: CGFloat, height: CGFloat) -> some View {
        if let entry = item.entry {
            let bytes: String = item.bytes.formatted(.byteCount(style: .file))
            let label = Text(entry.name + ", " + bytes)
            let tooltip = Text(entry.url.path + " · " + bytes)
            Button(action: { select(entry) }) { tile(item, width: width, height: height) }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .help(tooltip)
        } else {
            tile(item, width: width, height: height)
                .help(Text("\(item.count) smaller entries grouped together"))
        }
    }
    private func tile(_ item: StorageSpaceMapSnapshot.Item, width: CGFloat, height: CGFloat) -> some View {
        let selected = selectedURL != nil && item.entry?.url == selectedURL
        let border: Color = selected ? .white : .black.opacity(0.3)
        let borderWidth: CGFloat = selected ? 3 : 1
        return ZStack {
            (item.entry?.category.color ?? .gray).opacity(0.8)
            if width >= 70, height >= 35 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.caption.weight(.semibold)).lineLimit(2)
                    if height >= 55 { Text(item.bytes.formatted(.byteCount(style: .file))).font(.caption2).lineLimit(1) }
                }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(Rectangle().stroke(border, lineWidth: borderWidth))
        .clipped()
    }
}
#endif

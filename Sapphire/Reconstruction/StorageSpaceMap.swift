#if !SAPPHIRE_FULL_BUILD
import Foundation

struct StorageSpaceMapSnapshot {
    struct Item: Identifiable {
        let id: String
        let entry: StorageEntry?
        let count: Int
        let weight: Double
        let bytes: Int64
        var name: String { entry?.name ?? "Other (\(count))" }
    }
    let items: [Item]
    let positiveEntryCount: Int
    let omittedZeroSizeCount: Int
    let isDeepScan: Bool
    var rectangles: [CGRect] { StorageTreemapLayout.rectangles(weights: items.map(\.weight)) }
    static func make(from entries: [StorageEntry], maximumItems: Int, used: Int64,
                     total: Int64, deepScanEnabled: Bool, entriesSortedBySize: Bool) -> Self {
        // This chart describes the current filtered scan, not whole-volume usage.
        // The caller supplies direct entries, not overlapping recursive insights.
        // Deduplicate URL identities defensively.
        var seen = Set<URL>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        let positive = unique.filter { $0.size > 0 }.sorted {
            $0.size == $1.size ? $0.url.path < $1.url.path : $0.size > $1.size
        }
        let limit = min(128, max(1, maximumItems))
        let selectedCount = positive.count > limit ? max(0, limit - 1) : positive.count
        var items = positive.prefix(selectedCount).map {
            Item(id: $0.url.absoluteString, entry: $0, count: 1, weight: Double($0.size), bytes: $0.size)
        }
        let remainder = positive.dropFirst(selectedCount)
        if !remainder.isEmpty {
            let weight = remainder.reduce(0.0) { $0 + Double($1.size) }
            let bytes = remainder.reduce(Int64(0)) { value, entry in
                let (sum, overflow) = value.addingReportingOverflow(entry.size)
                return overflow ? Int64.max : sum
            }
            items.append(.init(id: "sapphire-space-map-other", entry: nil, count: remainder.count, weight: weight, bytes: bytes))
        }
        return .init(items: items, positiveEntryCount: positive.count,
                     omittedZeroSizeCount: unique.count - positive.count, isDeepScan: deepScanEnabled)
    }
}
#endif

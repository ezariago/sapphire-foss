import Foundation

func verifyStorageSpaceMap() {
    func entry(_ name: String, _ size: Int64) -> StorageEntry {
        StorageEntry(url: URL(fileURLWithPath: "/fixture/\(name)"), size: size, isDirectory: false)
    }
    func snapshot(_ entries: [StorageEntry], limit: Int = 48) -> StorageSpaceMapSnapshot {
        .make(from: entries, maximumItems: limit, used: Int64.max, total: 0, deepScanEnabled: true, entriesSortedBySize: false)
    }
    let values = [entry("c", 100), entry("a", 200), entry("b", 200), entry("empty", 0), entry("invalid", -1)]
    let full = snapshot(values)
    assert(full.items.map(\.name) == ["a", "b", "c"])
    assert(full.positiveEntryCount == 3 && full.omittedZeroSizeCount == 2 && full.isDeepScan)
    assert(snapshot(values.reversed()).items.map(\.id) == full.items.map(\.id))
    assert(snapshot(values + [values[0]]).items.count == 3)
    let grouped = snapshot(values, limit: 2)
    assert(grouped.items.count == 2 && grouped.items[1].entry == nil)
    assert(grouped.items[1].count == 2 && grouped.items[1].bytes == 300)
    assert(snapshot(values, limit: 0).items.first?.count == 3)
    let extreme = snapshot([entry("a", Int64.max), entry("b", Int64.max), entry("c", Int64.max)], limit: 1)
    assert(extreme.items[0].bytes == Int64.max && extreme.items[0].weight.isFinite)
    assert(snapshot((0..<1000).map { entry("\($0)", 100) }, limit: Int.max).items.count == 128)
    assert(snapshot([]).items.isEmpty)
    func verify(_ weights: [Double]) {
        let rectangles = StorageTreemapLayout.rectangles(weights: weights)
        assert(rectangles.count == weights.count)
        let maxWeight = weights.filter { $0.isFinite && $0 > 0 }.max() ?? 1
        let total = weights.filter { $0.isFinite && $0 > 0 }.reduce(0) { $0 + $1 / maxWeight }
        var area = 0.0
        for index in rectangles.indices {
            let rect = rectangles[index]
            assert(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite)
            assert(rect.minX >= -1e-12 && rect.minY >= -1e-12 && rect.maxX <= 1 + 1e-12 && rect.maxY <= 1 + 1e-12)
            assert(rect.width >= 0 && rect.height >= 0)
            let fraction = rect.width * rect.height
            area += fraction
            let expected = weights[index].isFinite && weights[index] > 0 ? weights[index] / maxWeight / total : 0
            assert(abs(fraction - expected) < 1e-10)
            for other in rectangles.indices where other > index {
                let intersection = rect.intersection(rectangles[other])
                assert(intersection.isNull || intersection.width * intersection.height < 1e-10)
            }
        }
        assert(abs(area - (total > 0 ? 1 : 0)) < 1e-10)
    }
    for weights: [Double] in [[], [0, -1, .nan, .infinity], [1], [1, 1], [20, 10, 5, 1],
                             [Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude],
                             (1...128).map { Double($0 * $0) }] { verify(weights) }
    print("Passed bounded Space Map grouping/identity/overflow and treemap area/proportion/non-overlap/finite geometry checks.")
}

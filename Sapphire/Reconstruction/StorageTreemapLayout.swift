#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Binary area partition, in unit coordinates. Input order supplies stable ties.
enum StorageTreemapLayout {
    static func rectangles(weights: [Double]) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: weights.count)
        let valid = weights.indices.filter { weights[$0].isFinite && weights[$0] > 0 }
        guard let largest = valid.map({ weights[$0] }).max() else { return result }
        // Normalize before summing to avoid overflow from malformed/extreme data.
        let normalized = valid.map { weights[$0] / largest }
        func partition(_ indices: ArraySlice<Int>, _ sizes: ArraySlice<Double>, _ rect: CGRect) {
            guard !indices.isEmpty else { return }
            if indices.count == 1 { result[indices.first!] = rect; return }
            let total = sizes.reduce(0, +)
            guard total > 0, total.isFinite else { return }
            var sum = 0.0
            var split = 1
            for position in 0..<(sizes.count - 1) {
                sum += sizes[sizes.startIndex + position]
                split = position + 1
                if sum >= total / 2 { break }
            }
            let fraction = min(1, max(0, sum / total))
            let first: CGRect
            let second: CGRect
            if rect.width >= rect.height {
                let width = rect.width * fraction
                first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
            } else {
                let height = rect.height * fraction
                first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
                second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
            }
            partition(indices.prefix(split), sizes.prefix(split), first)
            partition(indices.dropFirst(split), sizes.dropFirst(split), second)
        }
        partition(valid[...], normalized[...], CGRect(x: 0, y: 0, width: 1, height: 1))
        return result
    }
}
#endif

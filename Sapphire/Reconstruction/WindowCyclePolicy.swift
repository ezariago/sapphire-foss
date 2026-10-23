#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

/// Keep a stable ring even when AX returns the focused window first on each read.
struct WindowCyclePolicy {
    private(set) var order: [String] = []
    private var lastSelection: String?
    mutating func next(windows: [String], focused: String?) -> String? {
        let live = Set(windows)
        order.removeAll { !live.contains($0) }
        for id in windows where !order.contains(id) { order.append(id) }
        guard !order.isEmpty else { lastSelection = nil; return nil }
        let current = focused.flatMap { order.firstIndex(of: $0) }
            ?? lastSelection.flatMap { order.firstIndex(of: $0) }
        let next = current.map { ($0 + 1) % order.count } ?? 0
        lastSelection = order[next]
        return lastSelection
    }
}

struct WindowPreviewCandidate {
    let id: UInt32
    let title: String?
    let bounds: CGRect?
}

enum WindowPreviewMatcher {
    /// Never associate a thumbnail by title alone when multiple windows match.
    static func match(title: String, bounds: CGRect?, candidates: [WindowPreviewCandidate]) -> UInt32? {
        let accepts: (WindowPreviewCandidate) -> Bool = { candidate in
            if !title.isEmpty, let name = candidate.title, name != title { return false }
            if let bounds, let rect = candidate.bounds {
                return abs(bounds.minX - rect.minX) <= 2 && abs(bounds.minY - rect.minY) <= 2
                    && abs(bounds.width - rect.width) <= 2 && abs(bounds.height - rect.height) <= 2
            }
            return true
        }
        let matching = candidates.filter(accepts)
        return matching.count == 1 ? matching[0].id : nil
    }
}
#endif

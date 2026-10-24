#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Stateless wheel-only transforms. Continuous/phase-based gestures are bypassed by the adapter.
enum MouseScrollPolicy {
    struct Axis: Equatable {
        var lines: Int64
        var fixed: Double
        var pixels: Int64
    }
    static func transform(_ axis: Axis, speed: Double, inverted: Bool) -> Axis? {
        guard speed.isFinite, speed > 0, axis.fixed.isFinite else { return nil }
        let factor = min(4, max(0.25, speed)) * (inverted ? -1 : 1)
        func integer(_ value: Int64) -> Int64 {
            guard value != 0 else { return 0 }
            let scaled = Double(value) * factor
            // Integer-only consumers still get a step at speeds below one.
            let rounded = scaled.rounded()
            if rounded == 0 { return scaled < 0 ? -1 : 1 }
            return Int64(min(Double(Int32.max), max(Double(Int32.min), rounded)))
        }
        // CG's fixed representation is signed 16.16; saturate before conversion.
        let fixed = min(32767.99998474121, max(-32768, axis.fixed * factor))
        return Axis(lines: integer(axis.lines), fixed: fixed, pixels: integer(axis.pixels))
    }
}
#endif

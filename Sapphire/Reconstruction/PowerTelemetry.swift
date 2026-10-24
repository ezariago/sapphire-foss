import Foundation

/// A missing sensor is distinct from a valid zero-watt reading. Adapter ratings
/// and system load are never substituted for measured adapter input.
struct PowerTelemetry: Equatable {
    let system: Double?
    let adapter: Double?
    init(system: Double?, adapter: Double?) {
        self.system = Self.validWatts(system)
        self.adapter = Self.validWatts(adapter)
    }
    static func validWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    private var maximum: Double { max(system ?? 0, adapter ?? 0) }
    var systemFraction: Double { maximum > 0 ? (system ?? 0) / maximum : 0 }
    var adapterFraction: Double { maximum > 0 ? (adapter ?? 0) / maximum : 0 }
}

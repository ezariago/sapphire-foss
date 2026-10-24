/// Authorization callbacks may outlive the settings under which they began.
struct MonitoringDeliveryPolicy {
    enum Kind: String, Hashable, Sendable { case cpu, temperature, memoryPressure, lowDisk, lowBattery }
    struct Ticket: Sendable { fileprivate var generation: UInt64; fileprivate var kind: Kind }
    private var generation: UInt64 = 0
    private var active: Set<Kind> = []
    mutating func configure(_ active: Set<Kind>) { generation &+= 1; self.active = active }
    func ticket(for kind: Kind) -> Ticket? { active.contains(kind) ? Ticket(generation: generation, kind: kind) : nil }
    func isCurrent(_ ticket: Ticket) -> Bool { ticket.generation == generation && active.contains(ticket.kind) }
}

enum MonitoringThresholds {
    private static func normalize(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    static func cpu(_ value: Double) -> Double { normalize(value, range: 50...100, fallback: 90) }
    static func disk(_ value: Double) -> Double { normalize(value, range: 2...50, fallback: 10) }
    static func temperature(_ value: Double) -> Double { normalize(value, range: 70...105, fallback: 95) }
    static func battery(_ value: Double) -> Double { normalize(value, range: 5...50, fallback: 15) }
}

enum MonitoringSampleMath {
    static func cpuPercent(_ usage: Double) -> Double? {
        // Tick fractions can sum a few ULPs above one at full saturation.
        guard usage.isFinite, usage >= 0, usage <= 1.000001 else { return nil }
        return min(1, usage) * 100
    }
}

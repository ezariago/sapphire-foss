import Foundation
import Combine

struct PowerAdapterInfo: Equatable, Sendable {}
struct FixtureBatteryState { var level: Int; var isCharging: Bool; var isPluggedIn = false }
struct FixtureSensor { var key: String; var value: Double }
struct FixtureSensors { var sensors: [FixtureSensor] }
struct FixtureBatteryUsage {
    var timeToCharge = 0; var timeToEmpty = 0; var powerDraw = 0.0
    var amperage = 0; var voltage = 0.0
}
struct FixtureStatsPayload {
    var systemPower: Double?
    var sensors: FixtureSensors?
    var battery: FixtureBatteryUsage? = nil
}
@MainActor final class StatsManager: ObservableObject {
    static let shared = StatsManager()
    @Published var currentStats: FixtureStatsPayload?
}
@MainActor final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published var currentState: FixtureBatteryState?
}
@MainActor final class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var isLowPowerModeActive = false
    func isLowPowerModeEnabled() -> Bool { false }
}
@MainActor final class BatteryManager {
    static let shared = BatteryManager()
    func getBatteryTemperature() async -> Double { 0 }
    func getDesignCapacity() async -> Int { 0 }
    func getMaxCapacity() async -> Int { 0 }
    func getAppleMaxCapacity() async -> Int { 0 }
    func getCycleCount() async -> Int { 0 }
    func getBatteryHealth() async -> String { "Fixture" }
    func getPowerAdapterInfo() async -> PowerAdapterInfo? { nil }
}

import Foundation

@main struct PowerModelFixture {
    @MainActor static func flush() async { try! await Task.sleep(for: .milliseconds(50)) }
    @MainActor static func main() async {
        let stats = StatsManager.shared
        let model = BatteryStatsViewModel()
        model.start(); await flush()
        assert(!model.hasSystemPowerReading && !model.hasAdapterPowerReading)
        assert(!model.hasPowerSourceReading)
        BatteryMonitor.shared.currentState = .init(level: 80, isCharging: false, isPluggedIn: true)
        await flush()
        assert(model.hasPowerSourceReading && model.isPluggedIn && model.powerAdapterInfo == nil)
        BatteryMonitor.shared.currentState = nil
        await flush()
        assert(!model.hasPowerSourceReading && !model.isPluggedIn)
        stats.currentStats = .init(systemPower: 25, sensors: nil)
        await flush()
        assert(model.hasSystemPowerReading && model.systemPower == 25 && !model.hasAdapterPowerReading)
        stats.currentStats = .init(systemPower: 0, sensors: .init(sensors: [.init(key: "PDTR", value: 0)]))
        await flush()
        assert(model.hasSystemPowerReading && model.hasAdapterPowerReading && model.adapterPower == 0)
        stats.currentStats = .init(systemPower: .nan, sensors: .init(sensors: [.init(key: "PDTR", value: -5)]))
        await flush()
        assert(!model.hasSystemPowerReading && !model.hasAdapterPowerReading)
        stats.currentStats = .init(systemPower: 30, sensors: .init(sensors: [.init(key: "PDTR", value: 60)]))
        await flush()
        assert(model.systemPower == 30 && model.adapterPower == 60 && model.hasAdapterPowerReading)
        stats.currentStats = nil
        await flush()
        assert(!model.hasSystemPowerReading && !model.hasAdapterPowerReading)
        model.stop()
        stats.currentStats = .init(systemPower: 40, sensors: .init(sensors: [.init(key: "PDTR", value: 70)]))
        await flush()
        assert(!model.hasSystemPowerReading && !model.hasAdapterPowerReading)
        model.start(); await flush()
        assert(model.hasSystemPowerReading && model.systemPower == 40 && model.adapterPower == 70)
        model.stop()
        assert(!model.hasSystemPowerReading && !model.hasAdapterPowerReading)
        print("Passed production battery view-model publisher fixtures for missing/zero/invalid readings, clearing and stop/restart; only injected providers were used.")
    }
}

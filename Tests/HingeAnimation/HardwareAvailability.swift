import Foundation
@main struct HardwareAvailability {
    @MainActor static func main() {
        let sensor = LidAngleSensor.shared
        if CommandLine.arguments.contains("--cadence") {
            sensor.acquire(.hingeAnimationStandby)
            defer { sensor.release(.hingeAnimationStandby) }
            let started = ProcessInfo.processInfo.systemUptime
            var lastTick = sensor.tick
            var lastReport = started
            var reports = 0
            var largestGap = 0.0
            while ProcessInfo.processInfo.systemUptime - started < 2 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                if sensor.tick != lastTick {
                    let now = ProcessInfo.processInfo.systemUptime
                    largestGap = max(largestGap, now - lastReport)
                    lastReport = now; lastTick = sensor.tick; reports += 1
                }
            }
            let valid = sensor.isReporting && sensor.angle.isFinite && (0...180).contains(sensor.angle)
            print("Native standby cadence: reports=\(reports), largestObservedGap=\(largestGap), validAngle=\(valid). No desktop capture or physical movement requested.")
            precondition(valid && reports >= 10 && largestGap < 0.5, "Sensor did not sustain the hinge freshness requirement")
            return
        }
        if CommandLine.arguments.contains("--sample") {
            sensor.acquire(.systemEnhanceSettingsPreview)
            defer { sensor.release(.systemEnhanceSettingsPreview) }
            let valid = sensor.isReporting && sensor.angle.isFinite && (0...180).contains(sensor.angle)
            print("Bounded native sensor report: reporting=\(sensor.isReporting), validAngle=\(valid), tick=\(sensor.tick). Sensor client released on exit; no physical lid movement, desktop capture or power-setting change.")
            precondition(valid, "No valid native lid report was available")
            return
        }
        print("Read-only sensor discovery: available=\(sensor.isAvailable), reporting=\(sensor.isReporting). No sensor client acquired; no lid angle sample, desktop capture or physical movement requested.")
    }
}

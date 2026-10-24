import Foundation
@main struct HardwareAvailability {
    @MainActor static func main() {
        let sensor = LidAngleSensor.shared
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

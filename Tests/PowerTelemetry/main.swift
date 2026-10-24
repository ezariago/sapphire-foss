import Foundation

let missing = PowerTelemetry(system: nil, adapter: nil)
assert(missing.system == nil && missing.adapter == nil && missing.systemFraction == 0 && missing.adapterFraction == 0)
let noAdapterSensor = PowerTelemetry(system: 25, adapter: nil)
assert(noAdapterSensor.system == 25 && noAdapterSensor.adapter == nil) // Never display load as adapter input.
assert(noAdapterSensor.systemFraction == 1 && noAdapterSensor.adapterFraction == 0)
let zero = PowerTelemetry(system: 0, adapter: 0)
assert(zero.system == 0 && zero.adapter == 0 && zero.systemFraction == 0 && zero.adapterFraction == 0)
let valid = PowerTelemetry(system: 30, adapter: 60)
assert(valid.systemFraction == 0.5 && valid.adapterFraction == 1)
let batterySupplement = PowerTelemetry(system: 60, adapter: 30)
assert(batterySupplement.systemFraction == 1 && batterySupplement.adapterFraction == 0.5)
assert(PowerTelemetry.validWatts(.nan) == nil && PowerTelemetry.validWatts(.infinity) == nil)
assert(PowerTelemetry.validWatts(-1) == nil && PowerTelemetry.validWatts(-.infinity) == nil)
let extreme = PowerTelemetry(system: .greatestFiniteMagnitude, adapter: 1)
assert(extreme.systemFraction == 1 && extreme.adapterFraction.isFinite)
print("Passed missing/zero/invalid sensor distinction, no fabricated adapter fallback and finite comparative bar fixtures; no hardware setting or audio was changed.")

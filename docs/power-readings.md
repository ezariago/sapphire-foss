# Power-sensor availability

Updated 24 October 2026. The public battery widget/detail now preserve the
difference between missing telemetry and a measured zero. System-load and adapter
sensor values use the existing stats pipeline (`PSTR` and `PDTR` respectively).
Missing, negative or non-finite values produce an unavailable reading. Missing
payloads and stopped view models clear the power readings instead of keeping the
last number indefinitely.

The System Power headline uses the system-load reading. An unavailable adapter
sensor displays “Adapter —”; it no longer substitutes system load or charger
wattage. Zero watts remains a valid measurement when a sensor actually supplied
zero. Connection status uses the battery monitor's power-source state rather than
requiring nonzero rated wattage or cached adapter metadata. Unknown source state
is labelled unavailable. The debug menu labels the reported adapter
rating explicitly instead of presenting derived metadata as live input power.

The former single-color placeholder bar now compares the two readings on a shared
relative scale: system load above, adapter input below. An unavailable reading
has no filled bar. These are comparative bars, not a battery-charge/efficiency
calculation. Tooltip and accessibility text identify both readings.

`./scripts/test-power-telemetry.sh` tests missing/zero/invalid readings, absence of
the fabricated adapter fallback, and finite comparative fractions. It also
compiles the production `BatteryStatsViewModel` against injected stats/battery/
power-mode providers to verify publisher clearing, zero handling, invalid samples
and stop/restart. No real battery/helper is queried by those fixtures and no power
setting is changed. The full app build checks native view integration.

Actual `PDTR` availability, readings across chargers/docks and calibration against
hardware remain unverified. The existing sensor key is not assumed to work on
every Mac; unsupported sensors remain unavailable. Real connection changes,
helper failure/recovery and widget presentation remain attended checks. Adapter
metadata reported by IOPS is separate from the live sensor reading.

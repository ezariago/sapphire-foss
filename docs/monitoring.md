# Monitoring settings and alert delivery

Added settings UI on 24 October 2026 around the existing public monitoring
engines. Menu-bar readouts support CPU, memory and eligible-interface network
rates. Turning them off releases their polling requests and removes the item.
All-off component selection hides the item rather than displaying empty data.
Teardown now removes settings subscriptions and resets startup state, so a later
start can register monitoring again.

System alerts are opt-in. Enabling them asks macOS for notification permission;
viewing settings only reads the current permission state. CPU load, memory
pressure, low home-volume space, low battery and CPU-temperature alerts can be
configured separately. The UI reflects the existing sustained windows/cooldowns,
sensor limitations and battery hysteresis. Disk readings use the volume containing
the home folder, include purgeable estimates and are labelled in GiB. macOS Focus
and notification settings control actual presentation/sound.

Imported thresholds are normalized to the documented UI bounds and non-finite
values use defaults. CPU/temperature threshold changes start a fresh sustained
window. CPU sample validation permits floating-point rounding a few ULPs above
one at full load while rejecting malformed samples. Invalid clock/value data and
sum overflow clear the sustained window; clock rollback starts a fresh epoch.
Battery and disk latch inputs are validated before arithmetic or alerting.

Deferred notification authorization callbacks carry the active configuration
generation and alert kind. Settings revisions, disable/re-enable and stop
invalidate old deliveries before they can add a notification. Background disk
queries use the same guard before updating the latch. Once a request has been
handed to macOS, OS delivery is outside that guard. Already-delivered notifications
are not retracted by turning monitoring off.

`./scripts/test-monitoring.sh` tests sustained windows, missing observations,
cooldowns, clock rollback, invalid samples/overflow, bounded thresholds, battery/
disk hysteresis, network counter resets and stale authorization/disk-query tickets.
It does not request notification permission, post notifications, play sounds,
create CPU load or fill a disk. The full app build checks settings/engine wiring.

Native permission denial/recovery, actual menu-bar display/removal and restart,
real alert delivery/cooldowns and hardware sensor availability remain attended
checks. The UI alone does not prove those interactions. Adapter-power readings
and menu-bar profile automation are separate unfinished paths.

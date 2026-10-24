# Menu-bar profiles

The public engine now supports opt-in reveal conditions for battery percentage
(strictly below/above a valid 0–100 threshold), active charging, battery power,
a readable Wi-Fi connection and an exact Wi-Fi network name. Any condition in a
supported enabled profile can request reveal. No conditions means no reveal.

The engine reads current IOKit power-source information and, only for Wi-Fi
conditions, CoreWLAN's current SSID on a utility task. It does not scan networks,
associate/disassociate, change power settings or request Location permission.
An unavailable/redacted SSID cannot match either Wi-Fi condition. A readable
SSID is evidence of association, not internet reachability. See Apple's
[CoreWLAN interface](https://developer.apple.com/documentation/corewlan/cwinterface)
and [SSID API](https://developer.apple.com/documentation/corewlan/cwinterface/ssid()).

Reads run on enable/configuration changes and every 10 seconds while active.
Missing or invalid telemetry does not match. Readings older than 20 seconds,
clock rollback and late queries cannot retain a reveal. Settings changes,
disable/re-enable, stop/restart and sleep invalidate pending work immediately.
Wake starts a fresh read. The engine never runs a script.

Focus conditions, script conditions, and Space/Focus bindings remain
unimplemented. Adding unsupported conditions is disabled in the public settings;
imported profiles containing any unsupported condition or enabled Space/Focus binding remain
inactive with an explanation. Imported paths/arguments are preserved as data and
are never executed. Available Focus modes still return none.

A profile reveal expands items inline, suspends automatic rehide while requested,
and yields to Zen mode. Ending Zen reevaluates the current request. When a
profile-owned reveal ends, normal rehide behavior resumes; without auto-rehide,
collapse is requested only away from the menu bar with no open menu. Existing
manual reveals are not claimed as profile-owned. The engine communicates with
the existing status-bar controller; this does not add per-display menu bars.

`./scripts/test-menu-bar-profiles.sh` compiles the production policy and engine
against isolated settings and injected async readings. It covers unknown/invalid
telemetry, threshold edges, unsupported mixed profiles/bindings, exact SSID
matching, persistence, opt-in, disable/re-enable, deletion, restart, late samples,
freshness/clock rollback and simulated sleep/wake notifications. It does not
query actual Wi-Fi/power state, execute scripts, change system settings or create
menu-bar UI. The full app build checks integration. Actual menu-bar layout,
Zen/rehide/gesture coexistence, charger transitions, permissions and Wi-Fi
changes remain native checks. No physical Mac sleep test was performed.

## Host-display bindings

Profiles can now require a selected display to host Sapphire’s menu-bar control.
The controller supplies its actual status-item window screen, using the existing
stable/legacy identifier candidates. The engine does not infer a target from the
pointer, focused app or a merely connected external monitor. This scopes the
single existing menu-bar controller; it does not create independent per-monitor
menus or move the native menu bar.

A selected-display profile requires at least one matching stored binding. Unknown
host, empty selection and disconnected/nonmatching targets cannot reveal. All
displays accepts any known host. Existing unbound profiles retain their previous
behaviour. Malformed selected IDs/control characters or more than 64 bindings
keep the profile inactive; ignored old selected IDs do not disable All displays.
The settings retain disconnected choices with Remove/Clear controls.

The current host gates telemetry requests and is rechecked when async readings
finish. Host changes clear the prior reveal immediately, cancel its generation,
and request fresh eligible readings. Public window/screen notifications and the
existing timer detect changes; late results cannot reveal on a different host.
The engine owns the host context rather than trusting telemetry-provided IDs.
No new screen capture, display-control or location permission is requested.

Injected policy/engine checks pass alias matching, missing/unknown/empty scopes,
malformed/imported bindings, persistence, context-change notifications, late
queries, no telemetry query for excluded displays, and observer teardown. Actual
monitor hot-plug, mirrored displays, status-item migration and native reveal/
rehide remain hardware/UI checks. These tests do not manipulate physical screens
or change the user’s menu-bar configuration.

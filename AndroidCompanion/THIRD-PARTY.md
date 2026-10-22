# Third-party references and dependencies

The Gradle wrapper scripts/JAR were obtained from SimpleWear, commit
`1b7b3a5bfe6794bbe9a73f836a21a33b46d71dc0`; they retain their notices. The Apache
license is included in `third-party/gradle-wrapper-LICENSE.txt`.

SimpleWear's source was inspected to understand modern Android tethering support.
Its app implementation is not bundled or copied into this companion. The helper
uses the same documented general approach: a separately authorized Shizuku broker
for tethering. Android hidden interfaces remain supplied by the installed OS.

Maven dependencies are version-pinned in the module build files:

- ZXing Core 3.5.3 — Apache-2.0, https://github.com/zxing/zxing
- Shizuku API/provider 13.1.5 — Apache-2.0, https://github.com/RikkaApps/Shizuku-API
- HiddenApiBypass 6.1 — Apache-2.0, https://github.com/LSPosed/AndroidHiddenApiBypass
- JUnit 4.13.2 — EPL-1.0, https://github.com/junit-team/junit4 (tests only)
- JSON-java 20250517 — public domain, https://github.com/stleary/JSON-java (tests only)

The new companion does not include the proprietary Sapphire Android APK, source
recovered from it, its signing key, its databases or its private API credentials.

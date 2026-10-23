import Foundation
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SapphireDockTests-\(UUID().uuidString)")
let domain = "dev.sapphire.fixture.\(UUID().uuidString)"
let prefs = DockLayoutPreferences(domain: domain)
defer {
    CFPreferencesSetAppValue("persistent-apps" as CFString, nil, domain as CFString)
    for key in ["orientation", "tilesize", "autohide", "magnification"] { CFPreferencesSetAppValue(key as CFString, nil, domain as CFString) }
    CFPreferencesAppSynchronize(domain as CFString)
    try? FileManager.default.removeItem(at: temp)
}
var layout = DockLayout()
layout.name = "Fixture"
layout.applicationPaths = ["/Applications/Fixture.app", "/Applications/Other.app"]
layout.orientation = "left"
layout.tileSize = 64
layout.autohide = true
try prefs.apply(layout, backupDirectory: temp, applicationExists: { _ in true })
let captured = try prefs.capture(name: layout.name)
assert(captured.applicationPaths == layout.applicationPaths && captured.orientation == "left" && captured.tileSize == 64 && captured.autohide)
let data = try JSONEncoder().encode(DockLayoutDocument(presets: [layout]))
let decoded = try DockLayoutDocument.decode(data)
assert(decoded == [layout])
let files = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
assert(files.count == 1)
func rejected(_ block: () throws -> Void) {
    do { try block(); fatalError("Accepted invalid preset") } catch {}
}
for path in ["relative.app", "https://evil/a.app", "/Applications/../Bad.app", "/Applications/file.txt"] {
    var invalid = layout
    invalid.applicationPaths = [path]
    rejected { _ = try invalid.validated() }
}
rejected { try prefs.apply(layout, backupDirectory: temp, applicationExists: { _ in false }) }
let afterMissing = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
assert(afterMissing.count == 1)
var future = DockLayoutDocument(presets: [layout]); future.version = 999
rejected { _ = try DockLayoutDocument.decode(JSONEncoder().encode(future)) }
let legacy = try JSONDecoder().decode(DockLayout.self, from: Data("{\"name\":\"Old preset\"}".utf8))
assert(legacy.name == "Old preset" && legacy.applicationPaths.isEmpty)
rejected { _ = try legacy.validated() }
print("Passed Dock preset roundtrip, isolated preference application/backup, missing-app and malicious input rejection checks.")

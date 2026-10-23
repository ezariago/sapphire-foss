import Foundation
import AppKit
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
let hotkey = KeyboardShortcut(key: "1", modifiers: [.command, .option])
layout.shortcut = hotkey
try prefs.apply(layout, backupDirectory: temp, applicationExists: { _ in true })
let captured = try prefs.capture(name: layout.name)
assert(captured.applicationPaths == layout.applicationPaths && captured.orientation == "left" && captured.tileSize == 64 && captured.autohide)
let data = try JSONEncoder().encode(DockLayoutDocument(presets: [layout]))
let decoded = try DockLayoutDocument.decode(data)
assert(decoded == [layout] && decoded[0].shortcut == hotkey)
let imported = try DockLayoutDocument.presetsForImport(data, existingIDs: [layout.id])
assert(imported.count == 1 && imported[0].id != layout.id && imported[0].shortcut == nil)
assert(imported[0].applicationPaths == layout.applicationPaths)
assert(DockLayout.shortcutTarget(id: layout.id, expected: hotkey, presets: [layout], enabled: true, isDisabled: false) == layout)
assert(DockLayout.shortcutTarget(id: layout.id, expected: hotkey, presets: [layout], enabled: false, isDisabled: false) == nil)
assert(DockLayout.shortcutTarget(id: layout.id, expected: hotkey, presets: [layout], enabled: true, isDisabled: true) == nil)
assert(DockLayout.shortcutTarget(id: layout.id, expected: hotkey, presets: [], enabled: true, isDisabled: false) == nil)
var reassigned = layout; reassigned.shortcut = KeyboardShortcut(key: "2", modifiers: [.control])
assert(DockLayout.shortcutTarget(id: layout.id, expected: hotkey, presets: [reassigned], enabled: true, isDisabled: false) == nil)
let files = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
assert(files.count == 1)
func rejected(_ block: () throws -> Void) {
    do { try block(); fatalError("Accepted invalid preset") } catch {}
}
for shortcut in [KeyboardShortcut(key: "a", modifiers: []), KeyboardShortcut(key: "a", modifiers: [.shift]), KeyboardShortcut(key: "", modifiers: [.command]), KeyboardShortcut(key: String(repeating: "a", count: 41), modifiers: [.option])] {
    var invalid = layout; invalid.shortcut = shortcut
    rejected { _ = try invalid.validated() }
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
assert(legacy.name == "Old preset" && legacy.applicationPaths.isEmpty && legacy.shortcut == nil)
rejected { _ = try legacy.validated() }
print("Passed Dock preset roundtrip, isolated preference application/backup, missing-app/malicious input rejection, shortcut persistence/guards and import sanitization checks.")

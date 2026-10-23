#if !SAPPHIRE_FULL_BUILD
import Foundation

struct DockLayout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "New Preset"
    var applicationPaths: [String] = []
    var orientation = "bottom"
    var tileSize = 48.0
    var autohide = false
    var magnification = false
    var shortcut: KeyboardShortcut?

    enum CodingKeys: String, CodingKey { case id, name, applicationPaths, orientation, tileSize, autohide, magnification, shortcut }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Imported Preset"
        applicationPaths = try values.decodeIfPresent([String].self, forKey: .applicationPaths) ?? []
        orientation = try values.decodeIfPresent(String.self, forKey: .orientation) ?? "bottom"
        tileSize = try values.decodeIfPresent(Double.self, forKey: .tileSize) ?? 48
        autohide = try values.decodeIfPresent(Bool.self, forKey: .autohide) ?? false
        magnification = try values.decodeIfPresent(Bool.self, forKey: .magnification) ?? false
        shortcut = try values.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut)
    }

    static func isValidShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        !shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && shortcut.key.count <= 40 && !shortcut.key.contains("\0")
            && !shortcut.significantModifiers.intersection([.command, .option, .control]).isEmpty
    }

    static func shortcutTarget(id: UUID, expected: KeyboardShortcut, presets: [Self], enabled: Bool, isDisabled: Bool) -> Self? {
        guard enabled, !isDisabled, let layout = presets.first(where: { $0.id == id }),
              layout.shortcut == expected, (try? layout.validated()) != nil else { return nil }
        return layout
    }

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              ["left", "bottom", "right"].contains(orientation), tileSize.isFinite,
              (16...128).contains(tileSize), (1...200).contains(applicationPaths.count),
              Set(applicationPaths).count == applicationPaths.count,
              shortcut.map(Self.isValidShortcut) ?? true,
              applicationPaths.allSatisfy({ path in
                  path.hasPrefix("/") && path.utf8.count <= 4096 && !path.contains("\0")
                    && URL(fileURLWithPath: path).pathExtension.lowercased() == "app"
                    && !(path as NSString).pathComponents.contains("..")
              }) else { throw DockLayoutError.invalidPreset }
        return self
    }
}

enum DockLayoutError: LocalizedError {
    case invalidPreset, unsupportedVersion, missingApplication(String), preferencesFailed
    var errorDescription: String? {
        switch self {
        case .invalidPreset: "This Dock preset is empty or contains invalid settings, shortcuts or application paths."
        case .unsupportedVersion: "This Dock preset file uses an unsupported version."
        case .missingApplication(let path): "Install or locate the application before applying this preset: \(path)"
        case .preferencesFailed: "Dock preferences could not be saved. The previous values were restored."
        }
    }
}

struct DockLayoutDocument: Codable {
    var version = 1
    var presets: [DockLayout]
    static func presetsForImport(_ data: Data, existingIDs: Set<UUID>) throws -> [DockLayout] {
        var used = existingIDs
        return try decode(data).map { incoming in
            var layout = incoming
            layout.shortcut = nil
            while used.contains(layout.id) { layout.id = UUID() }
            used.insert(layout.id)
            return layout
        }
    }
    static func decode(_ data: Data) throws -> [DockLayout] {
        guard data.count <= 1_048_576 else { throw DockLayoutError.invalidPreset }
        let document = try JSONDecoder().decode(Self.self, from: data)
        guard document.version == 1 else { throw DockLayoutError.unsupportedVersion }
        guard (1...100).contains(document.presets.count), Set(document.presets.map(\.id)).count == document.presets.count else { throw DockLayoutError.invalidPreset }
        return try document.presets.map { try $0.validated() }
    }
}

/// This adapter accepts a test domain; tests never alter the user's Dock.
struct DockLayoutPreferences {
    var domain = "com.apple.dock"
    private static let keys = ["persistent-apps", "orientation", "tilesize", "autohide", "magnification"]
    func snapshot() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in Self.keys { values[key] = CFPreferencesCopyAppValue(key as CFString, domain as CFString) }
        return values
    }
    func capture(name: String) throws -> DockLayout {
        let values = snapshot()
        var layout = DockLayout()
        layout.name = name
        layout.applicationPaths = (values["persistent-apps"] as? [[String: Any]] ?? []).compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String,
                  let url = URL(string: raw), url.isFileURL else { return nil }
            return url.path
        }
        layout.orientation = values["orientation"] as? String ?? "bottom"
        layout.tileSize = (values["tilesize"] as? NSNumber)?.doubleValue ?? 48
        layout.autohide = (values["autohide"] as? NSNumber)?.boolValue ?? false
        layout.magnification = (values["magnification"] as? NSNumber)?.boolValue ?? false
        return try layout.validated()
    }
    func apply(_ layout: DockLayout, backupDirectory: URL, applicationExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws {
        let layout = try layout.validated()
        for path in layout.applicationPaths where !applicationExists(path) { throw DockLayoutError.missingApplication(path) }
        let before = snapshot()
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        // Back up before any mutation, including keys that were previously absent.
        let backup = try PropertyListSerialization.data(fromPropertyList: before, format: .xml, options: 0)
        try backup.write(to: backupDirectory.appendingPathComponent("Dock-before-\(UUID().uuidString).plist"), options: .atomic)
        let tiles = layout.applicationPaths.map { path -> [String: Any] in
            ["tile-type": "file-tile", "tile-data": ["file-data": ["_CFURLString": URL(fileURLWithPath: path).absoluteString, "_CFURLStringType": 15], "file-label": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, "file-type": 41]]
        }
        let after: [String: Any] = ["persistent-apps": tiles, "orientation": layout.orientation, "tilesize": layout.tileSize, "autohide": layout.autohide, "magnification": layout.magnification]
        for key in Self.keys { CFPreferencesSetAppValue(key as CFString, after[key] as CFPropertyList?, domain as CFString) }
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            for key in Self.keys { CFPreferencesSetAppValue(key as CFString, before[key] as CFPropertyList?, domain as CFString) }
            CFPreferencesAppSynchronize(domain as CFString)
            throw DockLayoutError.preferencesFailed
        }
    }
}
#endif

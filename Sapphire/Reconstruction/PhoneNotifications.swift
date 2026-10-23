import Foundation

struct PhoneNotification: Equatable, Identifiable {
    struct Action: Equatable, Identifiable {
        let id: String
        let title: String
        let allowsReply: Bool
    }
    let key: String
    let revision: String
    let appId: String
    let appName: String
    let title: String
    let text: String
    let clearable: Bool
    let isGeneral: Bool
    let isSystem: Bool
    let snapshot: Bool
    let actions: [Action]
    var id: String { key + ":" + revision }

    var isDiagnosticFixture: Bool {
        appId == "dev.sapphire.companion" && key.contains("|sapphire-notification-fixture|")
            && title == "Sapphire mirroring test"
    }
    var diagnosticFixtureState: String {
        guard isDiagnosticFixture else { return "absent" }
        switch text {
        case "Synthetic action verified.": return "action-verified"
        case "Synthetic reply verified.": return "reply-verified"
        case "Updated synthetic notification.": return "updated"
        default: return "posted"
        }
    }

    init?(payload: [String: PhoneJSON]) {
        func string(_ field: String, max: Int, required: Bool = false) -> String? {
            if let raw = payload[field], raw.string == nil { return nil }
            let value = payload[field]?.string ?? ""
            guard value.utf8.count <= max, !required || !value.isEmpty else { return nil }
            return value
        }
        guard let key = string("key", max: 1024, required: true),
              let revision = string("revision", max: 128, required: true),
              let appId = string("appId", max: 256, required: true),
              let appName = string("appName", max: 256),
              let title = string("title", max: 512),
              let text = string("text", max: 4096), !title.isEmpty || !text.isEmpty else { return nil }
        self.key = key; self.revision = revision; self.appId = appId
        self.appName = appName.isEmpty ? appId : appName
        self.title = title; self.text = text
        clearable = payload["clearable"]?.bool ?? false
        isGeneral = payload["isGeneral"]?.bool ?? false
        isSystem = payload["isSystem"]?.bool ?? false
        snapshot = payload["snapshot"]?.bool ?? false
        var actions: [Action] = []
        if let raw = payload["actions"] {
            guard case .array(let values) = raw else { return nil }
            guard values.count <= 4 else { return nil }
            for value in values {
                guard let object = value.object,
                      let id = object["id"]?.string, !id.isEmpty, id.utf8.count <= 128,
                      let title = object["title"]?.string, !title.isEmpty, title.utf8.count <= 128,
                      !actions.contains(where: { $0.id == id }) else { return nil }
                actions.append(Action(id: id, title: title, allowsReply: object["allowsReply"]?.bool ?? false))
            }
        }
        self.actions = actions
    }
}

/// Ephemeral, bounded state. Replayed events never trigger another alert.
struct PhoneNotificationStore {
    private(set) var entries: [PhoneNotification] = []
    private var dismissedIDs: [String] = []
    mutating func accept(_ entry: PhoneNotification, mutedAppIDs: Set<String> = []) -> Bool {
        guard !mutedAppIDs.contains(entry.appId), !dismissedIDs.contains(entry.id) else { return false }
        if entries.contains(where: { $0.id == entry.id }) { return false }
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        if entries.count > 30 { entries.removeLast(entries.count - 30) }
        return !entry.snapshot
    }
    mutating func remove(key: String, revision: String) -> Bool {
        let count = entries.count
        entries.removeAll { $0.key == key && $0.revision == revision }
        return entries.count != count
    }
    mutating func dismiss(_ entry: PhoneNotification) {
        if !dismissedIDs.contains(entry.id) {
            dismissedIDs.append(entry.id)
            if dismissedIDs.count > 128 { dismissedIDs.removeFirst() }
        }
        _ = remove(key: entry.key, revision: entry.revision)
    }
    /// Removes Mac copies without dismissing anything on the phone or suppressing
    /// the same revision when the app is allowed again.
    mutating func removeApps(_ appIDs: Set<String>) -> [PhoneNotification] {
        let removed = entries.filter { appIDs.contains($0.appId) }
        entries.removeAll { appIDs.contains($0.appId) }
        return removed
    }
    mutating func reset() { entries.removeAll(); dismissedIDs.removeAll() }
    func contains(key: String, revision: String) -> Bool {
        entries.contains { $0.key == key && $0.revision == revision }
    }
}

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

/// Text-only search: image upload and reverse-image engines are deliberately unsupported.
enum RegionTextSearchPolicy {
    static func query(_ text: String) -> String? {
        guard text.utf8.count <= 2048, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        let result = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return result.isEmpty ? nil : result
    }
    static func searchURL(query text: String) -> URL? {
        guard let query = query(text) else { return nil }
        var components = URLComponents()
        components.scheme = "https"; components.host = "www.google.com"; components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

@MainActor final class RegionTextSearchSession: ObservableObject {
    @Published var query = ""
    @Published private(set) var status = "Select a region to recognize text locally."
    @Published private(set) var busy = false
    private var enabled = false
    private var suspended = false
    private var epoch: UInt64 = 0
    private var task: Task<Void, Never>?
    private let capture: () async throws -> String
    private let open: (URL) -> Bool
    private let allowed: () -> Bool
    init(capture: @escaping () async throws -> String, open: @escaping (URL) -> Bool, allowed: @escaping () -> Bool = { true }) {
        self.capture = capture; self.open = open; self.allowed = allowed
    }
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled; clear()
    }
    func suspend(_ value: Bool) { suspended = value; clear() }
    func clear() {
        epoch &+= 1; task?.cancel(); query = ""
        status = enabled ? "Select a region to recognize text locally." : "Screen text search is off."
        // Keep busy until the previous provider actually finishes, even if it ignores cancellation.
    }
    func select() {
        guard enabled, !suspended, !busy, allowed() else { return }
        clear(); busy = true; status = "Select a region; press Escape to cancel."
        let stamp = epoch
        task = Task { [weak self, capture] in
            let result: Result<String, Error>
            do { result = .success(try await capture()) } catch { result = .failure(error) }
            guard let self else { return }
            defer { self.busy = false; self.task = nil }
            guard self.epoch == stamp, self.enabled, !self.suspended, self.allowed(), !Task.isCancelled else { return }
            switch result {
            case .success(let text):
                // Never keep the screenshot or a large recognized document in this review UI.
                if let normalized = RegionTextSearchPolicy.query(text) {
                    self.query = normalized; self.status = "Review the text, then choose Search Google."
                } else { self.status = "No usable text, or more than 2,048 bytes. Try a smaller region." }
            case .failure:
                self.status = "Selection cancelled or unavailable. Check Screen Recording permission and retry."
            }
        }
    }
    @discardableResult func search() -> Bool {
        guard enabled, !suspended, !busy, allowed(), let url = RegionTextSearchPolicy.searchURL(query: query) else { return false }
        let success = open(url)
        status = success ? "Requested a browser search." : "The browser could not open the search."
        return success
    }
}
#endif

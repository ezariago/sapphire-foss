import Foundation

@MainActor final class Probe {
    var starts = 0
    var continuation: CheckedContinuation<String, Error>?
    func capture() async throws -> String {
        starts += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ text: String) { continuation?.resume(returning: text); continuation = nil }
}
@main struct Checks {
    @MainActor static func drain() async { for _ in 0..<30 { await Task.yield() } }
    @MainActor static func main() async {
        assert(RegionTextSearchPolicy.query(" \nhello\t world ") == "hello world")
        assert(RegionTextSearchPolicy.query("bad\u{0}query") == nil)
        assert(RegionTextSearchPolicy.query(String(repeating: "é", count: 1025)) == nil)
        assert(RegionTextSearchPolicy.query(" \n ") == nil)
        let url = RegionTextSearchPolicy.searchURL(query: "site:example.org & q=other #? café")!
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        assert(parts.scheme == "https" && parts.host == "www.google.com" && parts.path == "/search")
        assert(parts.queryItems == [URLQueryItem(name: "q", value: "site:example.org & q=other #? café")])
        let probe = Probe(); var opened: [URL] = []
        let session = RegionTextSearchSession(capture: { try await probe.capture() }, open: { opened.append($0); return true })
        session.select(); await drain(); assert(probe.starts == 0)
        session.configure(enabled: true); session.select(); session.select(); await drain()
        assert(probe.starts == 1 && session.busy && opened.isEmpty)
        session.clear(); session.select(); assert(session.busy)
        probe.complete("stale secret"); await drain()
        assert(!session.busy && session.query.isEmpty && opened.isEmpty)
        session.select(); await drain(); probe.complete("  recognized\ntext "); await drain()
        assert(session.query == "recognized text" && opened.isEmpty)
        session.query = "edited & query"; assert(session.search() && opened.count == 1)
        assert(URLComponents(url: opened[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "edited & query")
        session.suspend(true); assert(session.query.isEmpty && !session.search())
        session.select(); await drain(); assert(probe.starts == 2)
        session.suspend(false); session.select(); await drain(); session.configure(enabled: false)
        probe.complete("disabled secret"); await drain(); assert(session.query.isEmpty && !session.search())
        session.configure(enabled: true); session.select(); await drain(); session.suspend(true)
        probe.complete("locked secret"); await drain(); assert(session.query.isEmpty && opened.count == 1)
        session.suspend(false); session.select(); await drain(); probe.complete(String(repeating:"x",count:2049)); await drain()
        assert(session.query.isEmpty && !session.search())
        print("Passed bounded text/query encoding, explicit browser delivery, single-flight selection, cancellation, disable and lock stale-result guards. No screen capture, browser or clipboard used.")
    }
}

#if !SAPPHIRE_FULL_BUILD
import Foundation

struct StoragePieSnapshot {
    struct Item: Identifiable {
        var id: String { category.rawValue }
        let category: StorageCategory
        let bytes: Int64
        let start: Double
        let end: Double
        var fraction: Double { end - start }
    }
    let items: [Item]
    let displayTotal: Int64
    static func make(_ sizes: [StorageCategory: Int64]) -> Self {
        let ordered = sizes.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        let total = ordered.reduce(0.0) { $0 + Double($1.value) }
        guard total > 0, total.isFinite else { return .init(items: [], displayTotal: 0) }
        var offset = 0.0, bytes: Int64 = 0
        let items = ordered.enumerated().map { index, value -> Item in
            let start = offset
            offset = index == ordered.count - 1 ? 1 : min(1, offset + Double(value.value) / total)
            let (sum, overflow) = bytes.addingReportingOverflow(value.value); bytes = overflow ? .max : sum
            return .init(category: value.key, bytes: value.value, start: start, end: offset)
        }
        return .init(items: items, displayTotal: bytes)
    }
}

struct StorageRetainedTreeSnapshot {
    struct Node: Identifiable {
        var id: URL { url }
        let url: URL
        let entry: StorageEntry?
        let isContext: Bool
        let descendants: [Node]
        var children: [Node]? { descendants.isEmpty ? nil : descendants }
        var name: String { entry?.name ?? url.lastPathComponent }
    }
    let roots: [Node]
    let retainedRecordCount: Int
    let omittedRecordCount: Int
    let contextFolderCount: Int
    let records: [URL: StorageEntry]
    private struct Builder { var entry: StorageEntry?; var children = Set<URL>() }
    static func key(for url: URL) -> URL { URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: false) }
    static func make(root: URL, direct: [StorageEntry], insights: [StorageEntry], search: String = "", category: StorageCategory? = nil,
                     maximumRecords: Int = 500, maximumNodes: Int = 1000) -> Self {
        guard root.isFileURL, root.host == nil || root.host == "" || root.host == "localhost", root.query == nil, root.fragment == nil else {
            return .init(roots: [], retainedRecordCount: 0, omittedRecordCount: direct.count + insights.count, contextFolderCount: 0, records: [:])
        }
        let root = Self.key(for: root)
        let rootParts = root.pathComponents
        let recordLimit = min(1000, max(1, maximumRecords)), nodeLimit = min(2000, max(1, maximumNodes))
        func relative(_ url: URL) -> [String]? {
            guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost", url.query == nil, url.fragment == nil else { return nil }
            guard url.path.utf8.count <= 8192, !url.path.contains("\0") else { return nil }
            let parts = Self.key(for: url).pathComponents
            guard parts.count > rootParts.count, parts.starts(with: rootParts) else { return nil }
            return Array(parts.dropFirst(rootParts.count))
        }
        guard root.isFileURL, root.query == nil, root.fragment == nil else {
            return .init(roots: [], retainedRecordCount: 0, omittedRecordCount: direct.count + insights.count, contextFolderCount: 0, records: [:])
        }
        var known: [URL: StorageEntry] = [:]
        for entry in direct + insights where relative(entry.url) != nil {
            let key = Self.key(for: entry.url)
            if known[key] == nil { known[key] = entry }
        }
        let selected = known.filter { key, entry in
            (search.isEmpty || key.path.localizedCaseInsensitiveContains(search)) && (category.map(entry.matches) ?? true)
        }.sorted { $0.value.size == $1.value.size ? $0.key.path < $1.key.path : $0.value.size > $1.value.size }
        var builders: [URL: Builder] = [:], rootChildren = Set<URL>(), kept: [URL: StorageEntry] = [:], retained = 0, omitted = 0
        var selectedKeys = Set<URL>()
        for (url, entry) in selected {
            guard retained < recordLimit, let parts = relative(url), parts.count <= 24 else { omitted += 1; continue }
            var path = root, chain: [URL] = [], blocked = false
            for (index, part) in parts.enumerated() {
                path.appendPathComponent(part, isDirectory: false)
                path = Self.key(for: path)
                if index < parts.count - 1, let ancestor = known[path], !ancestor.isDirectory || ancestor.isSymbolicLink || ancestor.isPackage {
                    blocked = true; break
                }
                chain.append(path)
            }
            guard !blocked, builders.count + chain.filter({ builders[$0] == nil }).count <= nodeLimit else { omitted += 1; continue }
            for (index, key) in chain.enumerated() {
                if builders[key] == nil { builders[key] = Builder(entry: known[key]) }
                if let record = builders[key]?.entry { kept[key] = record }
                if index == 0 { rootChildren.insert(key) } else { builders[chain[index - 1]]?.children.insert(key) }
            }
            builders[url]?.entry = entry; kept[url] = entry; selectedKeys.insert(url); retained += 1
        }
        func node(_ key: URL) -> Node {
            let value = builders[key]!
            let children = value.children.sorted { $0.path < $1.path }.map(node)
            return .init(url: key, entry: value.entry, isContext: !selectedKeys.contains(key), descendants: children)
        }
        return .init(roots: rootChildren.sorted { $0.path < $1.path }.map(node), retainedRecordCount: retained,
                     omittedRecordCount: omitted, contextFolderCount: builders.values.filter { $0.entry == nil }.count, records: kept)
    }
}
#endif

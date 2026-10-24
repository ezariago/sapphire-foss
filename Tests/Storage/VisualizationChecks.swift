import Foundation
func verifyStorageVisualizations() {
    let pie = StoragePieSnapshot.make([.caches: 3, .downloads: 1, .other: 0, .trash: -1])
    assert(pie.items.count == 2 && pie.displayTotal == 4 && pie.items[0].category == .caches)
    assert(pie.items[0].fraction == 0.75 && pie.items[1].start == 0.75 && pie.items[1].end == 1)
    let extreme = StoragePieSnapshot.make([.caches: .max, .downloads: .max])
    assert(extreme.displayTotal == .max && extreme.items.allSatisfy { $0.fraction == 0.5 })
    assert(StoragePieSnapshot.make([:]).items.isEmpty)
    let root = URL(fileURLWithPath: "/synthetic-storage-root")
    func entry(_ path: String, size: Int64 = 10, directory: Bool = false) -> StorageEntry {
        StorageEntry(url: root.appendingPathComponent(path), size: size, isDirectory: directory)
    }
    let folder = entry("folder", size: 100, directory: true)
    let nested = entry("folder/a/b/file.bin", size: 30)
    let direct = entry("top.bin", size: 70)
    let tree = StorageRetainedTreeSnapshot.make(root: root, direct: [folder, direct], insights: [nested, nested])
    assert(tree.roots.count == 2 && tree.retainedRecordCount == 3 && tree.contextFolderCount == 2)
    assert(tree.records.count == 3 && tree.records[nested.url] == nested)
    let branch = tree.roots.first { $0.url == folder.url }!
    assert(branch.entry?.size == 100 && branch.descendants.count == 1)
    assert(branch.descendants[0].entry == nil && branch.descendants[0].descendants[0].entry == nil)
    let slashedFolder = StorageEntry(url: URL(fileURLWithPath: folder.url.path, isDirectory: true), size: 100, isDirectory: true)
    let slashedTree = StorageRetainedTreeSnapshot.make(root: root, direct: [slashedFolder], insights: [nested])
    assert(slashedTree.roots.first?.entry == slashedFolder && slashedTree.records[StorageRetainedTreeSnapshot.key(for: slashedFolder.url)] == slashedFolder)
    let searched = StorageRetainedTreeSnapshot.make(root: root, direct: [folder, direct], insights: [nested], search: "file.bin")
    assert(searched.retainedRecordCount == 1 && searched.roots.count == 1 && searched.roots[0].entry == folder && searched.roots[0].isContext)
    let capped = StorageRetainedTreeSnapshot.make(root: root, direct: [folder, direct], insights: [nested], maximumRecords: 1)
    assert(capped.retainedRecordCount == 1 && capped.omittedRecordCount == 2)
    let nodeCapped = StorageRetainedTreeSnapshot.make(root: root, direct: [], insights: [nested], maximumNodes: 2)
    assert(nodeCapped.roots.isEmpty && nodeCapped.omittedRecordCount == 1)
    let deep = entry(Array(repeating: "folder", count: 25).joined(separator: "/") + "/file.bin")
    assert(StorageRetainedTreeSnapshot.make(root: root, direct: [], insights: [deep]).omittedRecordCount == 1)
    var link = folder; link.isSymbolicLink = true
    let blocked = StorageRetainedTreeSnapshot.make(root: root, direct: [link], insights: [nested])
    assert(blocked.roots.count == 1 && blocked.roots[0].children == nil && blocked.omittedRecordCount == 1)
    var package = folder; package.isPackage = true
    assert(StorageRetainedTreeSnapshot.make(root: root, direct: [package], insights: [nested]).omittedRecordCount == 1)
    let notFolder = entry("folder", directory: false)
    assert(StorageRetainedTreeSnapshot.make(root: root, direct: [notFolder], insights: [nested]).omittedRecordCount == 1)
    let outside = StorageEntry(url: URL(fileURLWithPath: "/synthetic-storage-root-other/file"), size: 10, isDirectory: false)
    assert(StorageRetainedTreeSnapshot.make(root: root, direct: [outside], insights: []).roots.isEmpty)
    assert(StorageRetainedTreeSnapshot.make(root: URL(string: "file://remote.invalid/synthetic-storage-root")!, direct: [direct], insights: []).roots.isEmpty)
    var categorized = nested; categorized.category = .downloads
    let filtered = StorageRetainedTreeSnapshot.make(root: root, direct: [folder, direct], insights: [categorized], category: .downloads)
    assert(filtered.retainedRecordCount == 1 && filtered.records[nested.url] == categorized)
    print("Passed primary allocation pie proportions/overflow and bounded retained-record tree ancestry/search/filter/context/duplicate/depth/symlink/package guards. Synthetic paths only; no filesystem reads.")
}

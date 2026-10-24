import Foundation

// Only unrelated app-level access/Space Map dependencies are supplied here.
// All scanning, filtering, duplicate hashing, capacity and removal guards use
// the production AppStorageModels.swift compiled with SAPPHIRE_STORAGE_FIXTURE.
enum StorageFixtureFeature { case basicStorageFeatures }
enum SubscriptionAccess { static func hasAccess(to feature: StorageFixtureFeature) -> Bool { true } }
struct StorageSpaceMapSnapshot {
    static func make(from entries: [StorageEntry], maximumItems: Int, used: Int64, total: Int64,
                     deepScanEnabled: Bool, entriesSortedBySize: Bool) -> Self { .init() }
}

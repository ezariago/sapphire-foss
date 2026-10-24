import Foundation

// Only unrelated app-level feature access is supplied here.
// All scanning, filtering, duplicate hashing, capacity and removal guards use
// the production AppStorageModels.swift compiled with SAPPHIRE_STORAGE_FIXTURE.
enum StorageFixtureFeature { case basicStorageFeatures }
enum SubscriptionAccess { static func hasAccess(to feature: StorageFixtureFeature) -> Bool { true } }

//
//  SubscriptionCore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine
import SwiftUI

public enum SubscriptionTier: String, Codable, CaseIterable {
    case free, basic, pro, ultra

    case core
}

public enum AppFeature: String, Codable, CaseIterable {
    case unlimitedLyricsFetch, translation, geminiLive, advancedFileConversion,
         priorityAutomation, betaSoftwareUpdates, circleToSearch, liveSports,
         financeWidget, sportsWidget, financeLiveActivity, prioritizedFeedback,
         appLock, focusProductiveAccess,
         menuBarProfiles, androidContinuitySyncMedia, androidContinuityWidgets,
         androidContinuityPhotoDisk, mediaTools, basicMouseSettings,
         dockPresets,
         continuityUniversalKeyboard, continuityEarbudHandoff,
         continuityHandoff, continuityDocumentScanning,
         continuityCameraAndMic, continuityMacTabsOnPhone,
         androidNotificationsOnMac, continuityCloudflareRelay, windowsPreview, dockPreview, allMouseSettings,
         surroundSound, snapZonesKeyboardShortcuts, emojiSuggestAsYouType,
         basicStorageFeatures, clipboardPicker, clipboardAdvancedTools, dmgInstaller,
         macScreenMirroringOnAndroid, macScreenExtensionOnMac, androidInstantHotspot,
         androidRemoteConnection, advancedStorageFeatures, batteryWidget, audio8D,
         storageWidgets, ocrFeature
}

public struct SubscriptionEntitlements: Codable, Equatable {
    public var tier: SubscriptionTier
    public var features: Set<AppFeature>
    public var expiresAt: Date?

    public static let free = SubscriptionEntitlements(tier: .free, features: Set(AppFeature.allCases), expiresAt: nil)
}

public enum SubscriptionFeatureCatalog {
    public static func features(for tier: SubscriptionTier) -> Set<AppFeature> { Set(AppFeature.allCases) }
    public static func minimumTier(for feature: AppFeature) -> SubscriptionTier { .free }
    public static func tierDisplayName(_ tier: SubscriptionTier) -> String { "FOSS" }
    public static func marketingSubtitle(for tier: SubscriptionTier) -> String { "Free and open source. No account or subscription required." }
    public static func marketingTierHighlights() -> [(tier: SubscriptionTier, features: [String])] {
        [(tier: .free, features: ["All implemented features", "No account required", "No subscription limits"])]
    }
}

public enum SubscriptionAccess {
    public static func hasAccess(to feature: AppFeature) -> Bool { true }
    public static func resolvedTier() -> SubscriptionTier { .free }
    public static func intelligenceDailyRunLimit() -> Int { .max }
}

public final class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()

    public var tierGradientColors: [Color] { [.gray, .gray.opacity(0.6)] }
    public var userInitials: String { "G" }
    public var tierLabel: String { "FOSS" }

    @Published public private(set) var entitlements: SubscriptionEntitlements = .free
    @Published public private(set) var accessibleFeatures: Set<AppFeature> = Set(AppFeature.allCases)

    public init() {}

    public var activeTier: SubscriptionTier { entitlements.tier }
    public var hasCorePlan: Bool { true }
    public var isSignedIn: Bool { false }
    public var userDisplayName: String { "Sapphire FOSS" }
    public var hasBetaSoftwareAccess: Bool { true }

    public func hasAccess(to feature: AppFeature) -> Bool { SubscriptionAccess.hasAccess(to: feature) }
    public func isFeatureEnabled(_ feature: AppFeature) -> Bool { SubscriptionAccess.hasAccess(to: feature) }
    public func applyLicensedTier(_ tier: SubscriptionTier) {}
    public func intelligenceDailyRunLimit() -> Int { .max }
    public func bootstrap(onCachedAccessReady: (@MainActor () -> Void)? = nil) async { await onCachedAccessReady?() }
    public func validateSubscriptionStatus() async {}
}

public final class FeatureGate {
    public static let shared = FeatureGate()

    private init() {}

    @discardableResult
    public func require(_ feature: AppFeature, message: String) -> Bool {
        SubscriptionAccess.hasAccess(to: feature)
    }
}

extension Notification.Name {
    public static let subscriptionPaywallRequested = Notification.Name("subscriptionPaywallRequested")
    public static let sapphireOpenAccountPane = Notification.Name("sapphireOpenAccountPane")
    public static let subscriptionSessionRevoked = Notification.Name("subscriptionSessionRevoked")
    public static let subscriptionEntitlementsDidChange = Notification.Name("subscriptionEntitlementsDidChange")
}
#endif
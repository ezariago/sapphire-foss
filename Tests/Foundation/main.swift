import Foundation
import SwiftUI

func expectRejected(_ action: () throws -> Void) {
    do { try action(); fatalError("Unexpectedly trusted invalid replacement") } catch {}
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let original = root.appendingPathComponent("Original.app")
let identical = root.appendingPathComponent("Identical.app")
let changed = root.appendingPathComponent("Changed.app")
let wrongID = root.appendingPathComponent("WrongID.app")
let tampered = root.appendingPathComponent("Tampered.app")
let unsigned = root.appendingPathComponent("Unsigned.app")
try AppSecurityValidator.validateReplacement(candidate: identical, replacing: original)
for rejected in [changed, wrongID, tampered, unsigned] {
    expectRejected { try AppSecurityValidator.validateReplacement(candidate: rejected, replacing: original) }
}
expectRejected { _ = try AppSecurityValidator.identity(at: root) }
let originalIdentity = try AppSecurityValidator.identity(at: original)
assert(originalIdentity.signingIdentifier == "dev.sapphire.security-fixture")
assert(AppSecurityValidator.applicationGroups(at: original).isEmpty)
for invalid in ["", ".", "..", "../escape", "a/b", "a\\b", "a\n"] {
    assert(!AppSecurityValidator.isSafeIdentifier(invalid))
}
for feature in AppFeature.allCases {
    assert(SubscriptionAccess.hasAccess(to: feature))
    assert(SubscriptionManager.shared.hasAccess(to: feature))
    assert(FeatureGate.shared.require(feature, message: "must never present a paywall"))
}
assert(SubscriptionEntitlements.free.features == Set(AppFeature.allCases))
assert(SubscriptionAccess.intelligenceDailyRunLimit() == Int.max)
assert(!SubscriptionManager.shared.isSignedIn)
assert(SubscriptionManager.shared.hasBetaSoftwareAccess)
print("Passed FOSS access checks and code-signature acceptance/rejection fixtures.")

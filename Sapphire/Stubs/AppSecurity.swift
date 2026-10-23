// Public code-signing validation used by updates and app-management tools.
#if !SAPPHIRE_FULL_BUILD
import Foundation
import Security

struct AppCodeSignatureIdentity: Equatable {
    let signingIdentifier: String
    let teamIdentifier: String?
    let bundleIdentifier: String
}

enum AppSecurityValidationError: LocalizedError {
    case notAnApplication
    case signatureInvalid(OSStatus)
    case missingSigningIdentifier
    case bundleIdentifierMismatch(expected: String, actual: String)
    case signingIdentifierMismatch
    case signerMismatch

    var errorDescription: String? {
        switch self {
        case .notAnApplication:
            "The downloaded item is not a valid application bundle."
        case .signatureInvalid(let status):
            "Code-signature validation failed: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))."
        case .missingSigningIdentifier:
            "The application has no signing identifier."
        case .bundleIdentifierMismatch(let expected, let actual):
            "The update is for \(actual), not \(expected)."
        case .signingIdentifierMismatch:
            "The update has a different code-signing identifier."
        case .signerMismatch:
            "The update does not satisfy the installed application's signing requirement. Locally ad-hoc signed builds must be updated manually."
        }
    }
}

enum AppSecurityValidator {
    private static let validationFlags = SecCSFlags(rawValue:
        kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw AppSecurityValidationError.signatureInvalid(status) }
    }

    private static func code(at url: URL) throws -> SecStaticCode {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundle = Bundle(url: url), bundle.bundleIdentifier != nil,
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppSecurityValidationError.notAnApplication
        }
        var code: SecStaticCode?
        try check(SecStaticCodeCreateWithPath(url as CFURL, [], &code))
        guard let code else { throw AppSecurityValidationError.notAnApplication }
        return code
    }

    static func identity(at bundleURL: URL, requireValidSignature: Bool = true) throws -> AppCodeSignatureIdentity {
        let code = try code(at: bundleURL)
        if requireValidSignature { try check(SecStaticCodeCheckValidity(code, validationFlags, nil)) }
        var information: CFDictionary?
        try check(SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information))
        let info = information as? [String: Any] ?? [:]
        guard let identifier = info[kSecCodeInfoIdentifier as String] as? String, !identifier.isEmpty else {
            throw AppSecurityValidationError.missingSigningIdentifier
        }
        return AppCodeSignatureIdentity(
            signingIdentifier: identifier,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            bundleIdentifier: Bundle(url: bundleURL)!.bundleIdentifier!
        )
    }

    static func validateReplacement(candidate: URL, replacing installed: URL) throws {
        let installedID = try identity(at: installed)
        let candidateID = try identity(at: candidate)
        guard candidateID.bundleIdentifier == installedID.bundleIdentifier else {
            throw AppSecurityValidationError.bundleIdentifierMismatch(expected: installedID.bundleIdentifier, actual: candidateID.bundleIdentifier)
        }
        guard candidateID.signingIdentifier == installedID.signingIdentifier else {
            throw AppSecurityValidationError.signingIdentifierMismatch
        }
        guard candidateID.teamIdentifier == installedID.teamIdentifier else {
            throw AppSecurityValidationError.signerMismatch
        }
        // Never derive trust from the downloaded candidate. An ad-hoc installed
        // app's requirement binds its hash, intentionally rejecting new builds.
        var requirement: SecRequirement?
        try check(SecCodeCopyDesignatedRequirement(try code(at: installed), [], &requirement))
        guard let requirement,
              SecStaticCodeCheckValidity(try code(at: candidate), validationFlags, requirement) == errSecSuccess else {
            throw AppSecurityValidationError.signerMismatch
        }
    }

    static func applicationGroups(at bundleURL: URL) -> Set<String> {
        guard (try? identity(at: bundleURL)) != nil,
              let code = try? code(at: bundleURL) else { return [] }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return Set((entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter(isSafeIdentifier))
    }

    static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier != "." && identifier != ".."
            && !identifier.contains("/") && !identifier.contains("\\")
            && !identifier.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
#endif

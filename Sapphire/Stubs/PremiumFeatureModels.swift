//
//  PremiumFeatureModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import Foundation

enum CaretPositionTracker {
    struct CaretInfo {
        let anchorPoint: NSPoint
        let lineNumber: Int?
        let isExact: Bool
    }

    static func caretInfo() -> CaretInfo? { nil }
    static func anchorPoint() -> NSPoint? { nil }
}

@MainActor
final class WiFiStatusMonitor: ObservableObject {
    struct State: Equatable {
        var isConnected = false
        var networkName: String?
        var isInterfacePowerOn = false
    }

    static let shared = WiFiStatusMonitor()
    @Published private(set) var state = State()

    private init() {}
    func startPolling() {}
    func stopPolling() {}
    func refresh(completion: (() -> Void)? = nil) { completion?() }
}


struct SnippetEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var trigger: String = ""
    var replacement: String = ""
    var isEnabled: Bool = true
}

enum EmojiSkinTone: String, Codable, CaseIterable, Identifiable {
    case none, light, mediumLight, medium, mediumDark, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Default"
        case .light: "Light"
        case .mediumLight: "Medium Light"
        case .medium: "Medium"
        case .mediumDark: "Medium Dark"
        case .dark: "Dark"
        }
    }
}

enum MouseButtonAction: String, Codable, CaseIterable, Identifiable {
    case none, back, forward, copy, paste, cut, undo, redo, selectAll
    case missionControl, launchpad, showDesktop, appSwitcher, spotlight
    case closeWindow, minimize, newTab, newWindow, reload, fullScreen
    case lockScreen, openSapphireSettings

    var id: String { rawValue }
}

struct MouseModifierSelection: Codable, Equatable {
    var rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(flags: NSEvent.ModifierFlags) {
        rawValue = flags.intersection([.control, .option, .command, .shift]).rawValue
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawValue)
            .intersection([.control, .option, .command, .shift])
    }

    static let control = MouseModifierSelection(flags: .control)
    static let `default` = MouseModifierSelection(flags: .control)
}

enum SEQuitProtectionMode: String, CaseIterable, Identifiable {
    case hold, doublePress, extraModifier
    var id: String { rawValue }
}

enum SEQuitProtectionExtraModifier: String, CaseIterable, Identifiable {
    case option, control, shift
    var id: String { rawValue }
}

enum SEDockClickAction: String, CaseIterable, Identifiable {
    case minimize, hide, cycle
    var id: String { rawValue }
}

enum SESuperKeyKey: String, CaseIterable, Identifiable {
    case rightCommand, leftCommand, capsLock
    var id: String { rawValue }
}

enum SESuperKeyCombo: String, CaseIterable, Identifiable {
    case hyper
    var id: String { rawValue }
}

enum SESuperKeyTapAction: String, CaseIterable, Identifiable {
    case none
    var id: String { rawValue }
}

enum SEPreviewLayout: String {
    case grid, list, carousel
}

enum SEPreviewTrigger: String {
    case hover, middleClick, modifierClick
}

enum SESwitcherActivation: String {
    case command, option, both
}

extension Settings {
    var systemEnhancePreviewLayout: SEPreviewLayout {
        get { SEPreviewLayout(rawValue: systemEnhancePreviewLayoutRaw) ?? .grid }
        set { systemEnhancePreviewLayoutRaw = newValue.rawValue }
    }

    var systemEnhanceWindowSwitcherLayout: SEPreviewLayout {
        get { SEPreviewLayout(rawValue: systemEnhanceWindowSwitcherLayoutRaw) ?? .grid }
        set { systemEnhanceWindowSwitcherLayoutRaw = newValue.rawValue }
    }

    var systemEnhancePreviewTrigger: SEPreviewTrigger {
        get { SEPreviewTrigger(rawValue: systemEnhancePreviewTriggerRaw) ?? .hover }
        set { systemEnhancePreviewTriggerRaw = newValue.rawValue }
    }

    var systemEnhanceSwitcherActivation: SESwitcherActivation {
        get { SESwitcherActivation(rawValue: systemEnhanceSwitcherActivationRaw) ?? .both }
        set { systemEnhanceSwitcherActivationRaw = newValue.rawValue }
    }

    var systemEnhanceQuitProtectionMode: SEQuitProtectionMode {
        get { SEQuitProtectionMode(rawValue: systemEnhanceQuitProtectionModeRaw) ?? .hold }
        set { systemEnhanceQuitProtectionModeRaw = newValue.rawValue }
    }

    var systemEnhanceQuitProtectionExtraModifier: SEQuitProtectionExtraModifier {
        get { SEQuitProtectionExtraModifier(rawValue: systemEnhanceQuitProtectionExtraModifierRaw) ?? .option }
        set { systemEnhanceQuitProtectionExtraModifierRaw = newValue.rawValue }
    }

    var systemEnhanceDockClickAction: SEDockClickAction {
        get { SEDockClickAction(rawValue: systemEnhanceDockClickActionRaw) ?? .minimize }
        set { systemEnhanceDockClickActionRaw = newValue.rawValue }
    }

    var superKeyKey: SESuperKeyKey {
        get { SESuperKeyKey(rawValue: superKeyKeyRaw) ?? .rightCommand }
        set { superKeyKeyRaw = newValue.rawValue }
    }

    var superKeyCombo: SESuperKeyCombo {
        get { SESuperKeyCombo(rawValue: superKeyComboRaw) ?? .hyper }
        set { superKeyComboRaw = newValue.rawValue }
    }

    var superKeyTapAction: SESuperKeyTapAction {
        get { SESuperKeyTapAction(rawValue: superKeyTapActionRaw) ?? .none }
        set { superKeyTapActionRaw = newValue.rawValue }
    }
}

#endif

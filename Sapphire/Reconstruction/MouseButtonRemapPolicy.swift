#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

enum MouseRemapCommand: String, CaseIterable {
    case back, forward, copy, paste, cut, undo, redo, selectAll
    case closeWindow, minimize, newTab, newWindow, reload, fullScreen, missionControl
    var shortcut: MouseMenuShortcut? {
        switch self {
        case .back: return MouseMenuShortcut(character: "[", modifiers: 0)
        case .forward: return MouseMenuShortcut(character: "]", modifiers: 0)
        case .copy: return MouseMenuShortcut(character: "C", modifiers: 0)
        case .paste: return MouseMenuShortcut(character: "V", modifiers: 0)
        case .cut: return MouseMenuShortcut(character: "X", modifiers: 0)
        case .undo: return MouseMenuShortcut(character: "Z", modifiers: 0)
        case .redo: return MouseMenuShortcut(character: "Z", modifiers: 1)
        case .selectAll: return MouseMenuShortcut(character: "A", modifiers: 0)
        case .closeWindow: return MouseMenuShortcut(character: "W", modifiers: 0)
        case .minimize: return MouseMenuShortcut(character: "M", modifiers: 0)
        case .newTab: return MouseMenuShortcut(character: "T", modifiers: 0)
        case .newWindow: return MouseMenuShortcut(character: "N", modifiers: 0)
        case .reload: return MouseMenuShortcut(character: "R", modifiers: 0)
        case .fullScreen: return MouseMenuShortcut(character: "F", modifiers: 4)
        case .missionControl: return nil
        }
    }
    var label: String {
        switch self {
        case .selectAll: return "Select All"
        case .closeWindow: return "Close Window"
        case .newTab: return "New Tab"
        case .newWindow: return "New Window"
        case .fullScreen: return "Full Screen"
        case .missionControl: return "Mission Control"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}
struct MouseMenuShortcut: Equatable { let character: String; let modifiers: Int }
struct MouseRemapApp: Equatable { let id: String; let pid: Int32; let launched: TimeInterval }
struct MouseRemapConfiguration: Equatable {
    var enabled = false
    var actions: [Int: String] = [:]
    var modified: [Int: String] = [:]
    var keyboardModifier: UInt64 = 1 << 18
    var modifierButtonEnabled = false
    var modifierButton = 3
    var excluded: Set<String> = []
    var protectsClose = false
    var closeExcluded: Set<String> = []
    var usesModifierButton: Bool {
        modifierButtonEnabled && (2...4).contains(modifierButton)
        && modified.contains { $0.key != modifierButton && (2...4).contains($0.key) && MouseRemapCommand(rawValue: $0.value) != nil }
    }
}
struct MouseRemapInput {
    enum Phase { case down, up, drag }
    let phase: Phase
    let button: Int
    let point: CGPoint
    let flags: UInt64
    let targetPID: Int64
    let synthetic: Bool
    let secureInput: Bool
    let now: TimeInterval
}
struct MouseRemapRequest: Equatable {
    let epoch: UInt64
    let app: MouseRemapApp
    let command: MouseRemapCommand
    let created: TimeInterval
}
enum MouseRemapDecision { case pass, swallow, execute(MouseRemapRequest) }

struct MouseButtonRemapPolicy {
    private struct Press {
        let app: MouseRemapApp
        let epoch: UInt64
        let point: CGPoint
        let started: TimeInterval
        var command: MouseRemapCommand?
        var modifier: Bool
        var cancelled = false
    }
    private(set) var epoch: UInt64 = 0
    private(set) var configuration = MouseRemapConfiguration()
    private(set) var app: MouseRemapApp?
    private var pressed: [Int: Press] = [:]
    private var lastClock: TimeInterval?
    static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
    mutating func configure(_ value: MouseRemapConfiguration) {
        guard value != configuration else { return }; configuration = value; invalidate()
    }
    mutating func foreground(_ value: MouseRemapApp?) { guard value != app else { return }; app = value; invalidate() }
    /// Preserve consumed-pair tombstones across normal changes. The original
    /// target must not receive an up after Sapphire swallowed its down.
    mutating func invalidate(retainConsumed: Bool = true) {
        epoch &+= 1; lastClock = nil
        if retainConsumed {
            for key in pressed.keys { pressed[key]?.cancelled = true; pressed[key]?.modifier = false }
        } else { pressed = [:] }
    }
    func accepts(_ request: MouseRemapRequest, now: TimeInterval) -> Bool {
        configuration.enabled && request.epoch == epoch && request.app == app
        && !configuration.excluded.contains(request.app.id)
        && now.isFinite && now >= request.created && now - request.created < 1
        && !(request.command == .closeWindow && configuration.protectsClose && !configuration.closeExcluded.contains(request.app.id))
    }
    mutating func handle(_ input: MouseRemapInput) -> MouseRemapDecision {
        guard (2...4).contains(input.button), !input.synthetic else { return .pass }
        guard input.now.isFinite, input.now >= 0, lastClock.map({ input.now >= $0 }) ?? true else {
            invalidate(); return finishInvalid(input)
        }
        lastClock = input.now
        if var press = pressed[input.button] {
            if input.secureInput { press.cancelled = true; pressed[input.button] = press }
            switch input.phase {
            case .down: return .swallow
            case .drag:
                let distance = hypot(input.point.x - press.point.x, input.point.y - press.point.y)
                if !press.modifier && (!distance.isFinite || distance > 6) { press.cancelled = true; pressed[input.button] = press }
                return .swallow
            case .up:
                pressed.removeValue(forKey: input.button)
                let distance = hypot(input.point.x - press.point.x, input.point.y - press.point.y)
                guard !press.modifier, !press.cancelled, !input.secureInput, let command = press.command,
                      press.epoch == epoch, press.app == app, configuration.enabled,
                      !configuration.excluded.contains(press.app.id), input.now >= press.started, input.now - press.started <= 2,
                      distance.isFinite, distance <= 6,
                      input.targetPID == 0 || input.targetPID == Int64(press.app.pid) else { return .swallow }
                let request = MouseRemapRequest(epoch: epoch, app: press.app, command: command, created: input.now)
                return accepts(request, now: input.now) ? .execute(request) : .swallow
            }
        }
        guard input.phase == .down, configuration.enabled, !input.secureInput,
              !CGEventFlags(rawValue: input.flags).contains(.maskSecondaryFn),
              input.point.x.isFinite, input.point.y.isFinite, let app, app.pid > 0,
              app.launched.isFinite, !configuration.excluded.contains(app.id),
              input.targetPID == 0 || input.targetPID == Int64(app.pid) else { return .pass }
        let flags = input.flags & Self.modifierMask
        let keyboardAlternate = configuration.keyboardModifier != 0 && configuration.keyboardModifier & ~Self.modifierMask == 0 && flags == configuration.keyboardModifier
        guard flags == 0 || keyboardAlternate else { return .pass }
        if configuration.usesModifierButton && input.button == configuration.modifierButton {
            pressed[input.button] = .init(app: app, epoch: epoch, point: input.point, started: input.now, command: nil, modifier: true)
            return .swallow
        }
        let mouseAlternate = pressed.values.contains { $0.modifier && !$0.cancelled && $0.epoch == epoch }
        let raw = (keyboardAlternate || mouseAlternate ? configuration.modified : configuration.actions)[input.button] ?? "none"
        guard let command = MouseRemapCommand(rawValue: raw),
              !(command == .closeWindow && configuration.protectsClose && !configuration.closeExcluded.contains(app.id)) else { return .pass }
        pressed[input.button] = .init(app: app, epoch: epoch, point: input.point, started: input.now, command: command, modifier: false)
        return .swallow
    }
    private mutating func finishInvalid(_ input: MouseRemapInput) -> MouseRemapDecision {
        guard pressed[input.button] != nil else { return .pass }
        if input.phase == .up { pressed.removeValue(forKey: input.button) }
        return .swallow
    }
}

/// Bounded traversal is shared with the real AX adapter; no menu titles are read.
enum MouseMenuSearch {
    static func find<Node>(_ root: Node, shortcut: MouseMenuShortcut, now: () -> TimeInterval,
                           children: (Node) -> [Node]?, command: (Node) -> MouseMenuShortcut?) -> Node? {
        let start = now()
        guard start.isFinite, start >= 0 else { return nil }
        var pending: [(Node, Int)] = [(root, 0)], visited = 0
        while let (node, depth) = pending.popLast() {
            let clock = now()
            guard clock.isFinite, clock >= start, clock - start < 0.4, visited < 128 else { return nil }
            visited += 1
            let matched = command(node) == shortcut
            let after = now()
            guard after.isFinite, after >= clock, after - start < 0.4 else { return nil }
            if matched { return node }
            guard depth < 5, let next = children(node), next.count <= 256 else { continue }
            pending.append(contentsOf: next.prefix(64).reversed().map { ($0, depth + 1) })
        }
        return nil
    }
}
#endif

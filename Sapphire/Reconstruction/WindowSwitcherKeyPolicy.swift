#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Pure input policy; the event tap never performs AX work or window actions.
struct WindowSwitcherKeyPolicy {
    enum Action: Equatable {
        case advance(reverse: Bool), move(Int), commit, cancel, cancelAndPass, close, quit, suppress
    }
    private enum Modifier: Equatable { case command, option }
    private(set) var enabled = false
    private(set) var epoch: UInt64 = 0
    private(set) var active = false
    private var activation = "both"
    private var columns = 3
    private var heldModifier = Modifier.option
    private var consumedKeys = Set<Int>()

    @discardableResult
    mutating func configure(enabled: Bool, activation: String, columns: Int) -> Bool {
        let activation = ["command", "option"].contains(activation) ? activation : "both"
        let columns = max(1, columns)
        guard self.enabled != enabled || self.activation != activation || self.columns != columns else { return false }
        self.enabled = enabled; self.activation = activation; self.columns = columns
        reset()
        return true
    }
    mutating func reset() { active = false; consumedKeys.removeAll(); epoch &+= 1 }
    mutating func flagsChanged(command: Bool, option: Bool) -> Action? {
        guard enabled, active else { return nil }
        if heldModifier == .command ? !command : !option { active = false; return .commit }
        return nil
    }
    mutating func keyUp(_ key: Int) -> Action? {
        enabled && consumedKeys.remove(key) != nil ? .suppress : nil
    }
    mutating func keyDown(_ key: Int, command: Bool, option: Bool, control: Bool, shift: Bool) -> Action? {
        guard enabled else { return nil }
        // Recover safely if a modifier-release event was lost: ordinary typing
        // must never close/quit the selected window or app.
        if active && (heldModifier == .command ? !command : !option) {
            active = false; epoch &+= 1
            return consumedKeys.contains(key) ? .cancel : .cancelAndPass
        }
        // Do not leak repeats of a consumed command into another app after commit.
        if !active, consumedKeys.contains(key) { return .suppress }
        if control {
            guard active else { return nil }
            active = false; epoch &+= 1
            return .cancelAndPass
        }
        if key == 48, (activation != "option" && command) || (activation != "command" && option) {
            active = true
            heldModifier = activation == "option" || !command ? .option : .command
            consumedKeys.insert(key)
            return .advance(reverse: shift)
        }
        guard active else { return nil }
        let action: Action
        switch key {
        case 123: action = .move(-1)
        case 124: action = .move(1)
        case 125: action = .move(columns)
        case 126: action = .move(-columns)
        case 36: active = false; action = .commit
        case 53: active = false; epoch &+= 1; action = .cancel
        case 12: active = false; action = .quit
        case 13: active = false; action = .close
        default:
            active = false; epoch &+= 1
            return .cancelAndPass
        }
        consumedKeys.insert(key)
        return action
    }
}
#endif

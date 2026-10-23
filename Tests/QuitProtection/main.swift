import Foundation
var policy = QuitProtectionPolicy()
func press(_ mode: String, _ now: Double, repeatKey: Bool = false, modifier: Bool = false, key: String = "app:Q") -> Bool {
    policy.keyDown(key: key, mode: mode, now: now, holdInterval: 1.2, doubleInterval: 0.5, isRepeat: repeatKey, hasExtraModifier: modifier)
}
assert(!press("hold", 0)); assert(!press("hold", 1)); assert(press("hold", 1.21))
assert(!press("hold", 2)); policy.keyUp(key: "app:Q"); assert(!press("hold", 3))
policy.reset()
assert(!press("doublePress", 10)); assert(!press("doublePress", 10.1, repeatKey: true)); assert(press("doublePress", 10.2))
policy.releaseHeldKeys()
assert(!press("doublePress", 20)); assert(!press("doublePress", 21)); assert(press("doublePress", 21.1))
policy.reset()
assert(!press("doublePress", 30)); assert(!press("doublePress", 30.1, key: "different:Q"))
assert(!press("extraModifier", 40)); assert(press("extraModifier", 40, modifier: true))
print("Passed quit/close hold, double-press, repeat suppression, app isolation and modifier policy checks.")

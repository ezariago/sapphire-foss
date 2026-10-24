import Foundation
import CoreGraphics
@main struct Checks {
    @MainActor static func main() async {
        let app = MouseRemapApp(id: "fixture.app", pid: 42, launched: 10)
        var config = MouseRemapConfiguration(enabled: true, actions: [2: "copy", 3: "back", 4: "none"], modified: [2: "paste"])
        func fresh(_ configuration: MouseRemapConfiguration? = nil) -> MouseButtonRemapPolicy {
            var policy = MouseButtonRemapPolicy(); policy.configure(configuration ?? config); policy.foreground(app); return policy
        }
        func input(_ phase: MouseRemapInput.Phase, button: Int = 2, x: Double = 10, flags: UInt64 = 0,
                   pid: Int64 = 42, synthetic: Bool = false, secure: Bool = false, now: Double = 100) -> MouseRemapInput {
            .init(phase: phase, button: button, point: CGPoint(x: x, y: 10), flags: flags, targetPID: pid, synthetic: synthetic, secureInput: secure, now: now)
        }
        func pass(_ decision: MouseRemapDecision) { guard case .pass = decision else { fatalError("Expected native pass") } }
        func swallow(_ decision: MouseRemapDecision) { guard case .swallow = decision else { fatalError("Expected consumed event") } }
        func request(_ decision: MouseRemapDecision) -> MouseRemapRequest { guard case .execute(let value) = decision else { fatalError("Expected menu action") }; return value }
        var policy = fresh()
        swallow(policy.handle(input(.down))); swallow(policy.handle(input(.down)))
        let copied = request(policy.handle(input(.up, now: 100.1)))
        assert(copied.command == .copy && policy.accepts(copied, now: 100.9))
        assert(!policy.accepts(copied, now: 101.1) && !policy.accepts(copied, now: .nan))
        pass(policy.handle(input(.up, now: 100.2)))
        policy = fresh(); swallow(policy.handle(input(.down))); swallow(policy.handle(input(.drag, x: 17))); swallow(policy.handle(input(.up, x: 17)))
        policy = fresh(); swallow(policy.handle(input(.down))); swallow(policy.handle(input(.up, now: 102.1)))
        for invalid in [Double.nan, Double.infinity, -1] {
            policy = fresh(); swallow(policy.handle(input(.down))); swallow(policy.handle(input(.up, now: invalid)))
        }
        policy = fresh(); pass(policy.handle(input(.down, button: 4))); pass(policy.handle(input(.up, button: 4)))
        pass(policy.handle(input(.down, button: 0))); pass(policy.handle(input(.down, button: 1)))
        policy = fresh(); pass(policy.handle(input(.down, synthetic: true))); pass(policy.handle(input(.up)))
        policy = fresh(); pass(policy.handle(input(.down, secure: true)))
        swallow(policy.handle(input(.down))); swallow(policy.handle(input(.up, secure: true)))
        policy = fresh(); pass(policy.handle(input(.down, pid: 43)))
        swallow(policy.handle(input(.down))); swallow(policy.handle(input(.up, pid: 43)))
        policy = fresh(); swallow(policy.handle(input(.down, flags: 1 << 18)))
        assert(request(policy.handle(input(.up, flags: 1 << 18))).command == .paste)
        policy = fresh(); pass(policy.handle(input(.down, flags: (1 << 18) | (1 << 20))))
        pass(policy.handle(input(.down, flags: CGEventFlags.maskSecondaryFn.rawValue)))
        policy = fresh(); swallow(policy.handle(input(.down)))
        policy.foreground(.init(id: "other.fixture", pid: 43, launched: 11)); swallow(policy.handle(input(.up)))
        assert(!policy.accepts(copied, now: 100.2))
        policy = fresh(); swallow(policy.handle(input(.down)))
        var disabled = config; disabled.enabled = false; policy.configure(disabled); policy.configure(config)
        swallow(policy.handle(input(.up))); assert(!policy.accepts(copied, now: 100.2))
        policy = fresh(); swallow(policy.handle(input(.down))); policy.invalidate(retainConsumed: false); pass(policy.handle(input(.up)))
        var unsupported = config; unsupported.actions[2] = "launchpad"
        policy = fresh(unsupported); pass(policy.handle(input(.down)))
        unsupported.actions[2] = "closeWindow"; unsupported.protectsClose = true
        policy = fresh(unsupported); pass(policy.handle(input(.down)))
        unsupported.closeExcluded = [app.id]; policy = fresh(unsupported)
        swallow(policy.handle(input(.down))); assert(request(policy.handle(input(.up))).command == .closeWindow)
        var system = config; system.actions[2] = "missionControl"
        policy = fresh(system); swallow(policy.handle(input(.down)))
        let mission = request(policy.handle(input(.up, now: 100.1)))
        assert(mission.command == .missionControl && mission.command.shortcut == nil)
        assert(policy.accepts(mission, now: 100.2))
        policy.invalidate(); assert(!policy.accepts(mission, now: 100.2))
        system.modifierButtonEnabled = true; system.modifierButton = 3; system.modified[2] = "missionControl"
        assert(system.usesModifierButton)
        policy = fresh(system); swallow(policy.handle(input(.down, button: 3))); swallow(policy.handle(input(.down)))
        assert(request(policy.handle(input(.up))).command == .missionControl)
        swallow(policy.handle(input(.up, button: 3)))
        var excluded = config; excluded.excluded = [app.id]; policy = fresh(excluded); pass(policy.handle(input(.down)))
        config.modifierButtonEnabled = true; config.modifierButton = 3
        policy = fresh(); pass(policy.handle(input(.down, button: 3, flags: 1 << 20)))
        swallow(policy.handle(input(.down, button: 3)))
        swallow(policy.handle(input(.down))); assert(request(policy.handle(input(.up))).command == .paste)
        swallow(policy.handle(input(.up, button: 3)))
        var unusedModifier = config; unusedModifier.modified = [:]
        policy = fresh(unusedModifier); swallow(policy.handle(input(.down, button: 3)))
        assert(request(policy.handle(input(.up, button: 3))).command == .back)
        policy = fresh(); policy.foreground(.init(id: app.id, pid: app.pid, launched: 12)); assert(!policy.accepts(copied, now: 100.2))
        let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: CGPoint(x: 3, y: 4), mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3); event.setIntegerValueField(.eventTargetUnixProcessID, value: 42)
        event.flags = .maskControl
        let adapted = MouseButtonEventAdapter.input(type: .otherMouseDown, event: event, secureInput: false, now: 100)!
        assert(adapted.button == 3 && adapted.flags == CGEventFlags.maskControl.rawValue && adapted.point == CGPoint(x: 3, y: 4))
        event.setIntegerValueField(.eventSourceUserData, value: 123)
        assert(MouseButtonEventAdapter.input(type: .otherMouseDown, event: event, secureInput: false, now: 100)!.synthetic)
        assert(MouseButtonEventAdapter.input(type: .leftMouseDown, event: event, secureInput: false, now: 100) == nil)
        let tree = [0: [1, 2], 1: [3], 2: [4]]
        assert(MouseMenuSearch.find(0, shortcut: MouseRemapCommand.copy.shortcut!, now: { 100 }, children: { tree[$0] }, command: { $0 == 3 ? .init(character: "C", modifiers: 0) : nil }) == 3)
        var visits = 0
        assert(MouseMenuSearch.find(0, shortcut: MouseRemapCommand.copy.shortcut!, now: { visits += 1; return Double(visits) / 100 }, children: { [$0 + 1] }, command: { _ in nil }) == nil)
        assert(visits < 128) // Depth bound also constrains this cycle-like chain.
        var slowClock = 100.0
        assert(MouseMenuSearch.find(0, shortcut: MouseRemapCommand.copy.shortcut!, now: { slowClock }, children: { _ in nil }, command: { _ in
            slowClock += 0.5; return MouseRemapCommand.copy.shortcut
        }) == nil)
        let req = MouseRemapRequest(epoch: 1, app: app, command: .copy, created: 100)
        var clock = 100.0, valid = true, resolved = 0, performed = 0, reports = 0
        var continuation: CheckedContinuation<Int?, Never>?
        let delivery = MouseMenuDelivery<Int>(clock: { clock }, validate: { _ in valid }, resolve: { _ in
            resolved += 1; return await withCheckedContinuation { continuation = $0 }
        }, perform: { value, _ in performed += 1; return value == 7 }, report: { success in reports += 1; assert(success) })
        delivery.submit(req); delivery.submit(req)
        for _ in 0..<20 { await Task.yield() }
        assert(resolved == 1 && delivery.busy)
        delivery.stop(); delivery.start(); continuation!.resume(returning: 7); continuation = nil
        for _ in 0..<20 { await Task.yield() }
        assert(performed == 0 && !delivery.busy)
        delivery.submit(req)
        for _ in 0..<20 { await Task.yield() }
        continuation!.resume(returning: 7); continuation = nil
        for _ in 0..<20 { await Task.yield() }
        assert(performed == 1 && reports == 1 && !delivery.busy)
        delivery.submit(req)
        for _ in 0..<20 { await Task.yield() }
        clock = 101; continuation!.resume(returning: 7); continuation = nil
        for _ in 0..<20 { await Task.yield() }
        assert(performed == 1 && !delivery.busy)
        clock = 100; delivery.submit(req)
        for _ in 0..<20 { await Task.yield() }
        valid = false; continuation!.resume(returning: 7); continuation = nil
        for _ in 0..<20 { await Task.yield() }
        assert(performed == 1 && !delivery.busy)
        delivery.stop()
        print("Passed production mouse-button pairing, modifiers, exclusions, protected-close/drag/hold/synthetic/target/clock refusal, real unposted CGEvent adaptation, bounded menu search and stale single-flight async delivery checks. No input was posted or real menu command invoked.")
    }
}

import Foundation
import CoreGraphics
@main struct Checks {
    @MainActor static func main() async {
        assert(HingeAnimationSample.isFresh(readAt: 100, now: 100.5))
        for (reading, now) in [(Optional<Double>.none, 100.0), (100, 100.501), (100, 99), (.nan, 100), (100, .infinity), (-1, 0)] {
            assert(!HingeAnimationSample.isFresh(readAt: reading, now: now))
        }
        let target = HingeDisplayTarget(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), pixelWidth: 3024, pixelHeight: 1964)
        assert(target.isValid && target.captureDimensions.0 == 2048 && target.captureDimensions.1 < 2048)
        var config = HingeAnimationConfiguration(enabled: true)
        var sample = HingeAnimationSample(now: 100, angle: 80, available: true, reporting: true, permission: true, unlocked: true, target: target)
        var policy = HingeAnimationState(); policy.configure(config); policy.update(sample)
        assert(policy.ticket == nil && policy.phase == .waitingForOpen)
        sample.angle = 100; policy.update(sample); assert(policy.phase == .ready)
        sample.angle = 60; policy.update(sample)
        let ticket = policy.ticket!
        assert(policy.phase == .capturing && policy.visual!.dim <= 0.7 && policy.visual!.blur <= 135)
        assert(policy.complete(ticket, now: 101, success: true) && policy.phase == .active)
        sample.now = 103; sample.angle = 0; policy.update(sample)
        assert(policy.visual!.progress == 1 && policy.visual!.dim == 0.7)
        sample.now = 104; policy.update(sample); assert(policy.ticket == nil && policy.phase == .timedOut)
        sample.now = 105; policy.update(sample); assert(policy.ticket == nil)
        sample.angle = 96; policy.update(sample); sample.angle = 70; policy.update(sample)
        let stale = policy.ticket!
        config.enabled = false; policy.configure(config); config.enabled = true; policy.configure(config)
        assert(!policy.complete(stale, now: 105, success: true))
        policy.update(sample); assert(policy.ticket == nil)
        sample.angle = 100; policy.update(sample); sample.angle = 70; policy.update(sample)
        sample.now = 107; policy.update(sample); assert(policy.phase == .captureFailed && policy.ticket == nil)
        for bad in [Double.nan, Double.infinity, -1, 181] {
            sample.angle = bad; policy.update(sample); assert(policy.phase == .invalidReading && policy.ticket == nil)
        }
        sample.angle = 100; sample.now = 200; policy.update(sample); sample.angle = 70; policy.update(sample)
        sample.now = 199; policy.update(sample); assert(policy.phase == .invalidReading && policy.ticket == nil)
        sample.now = 300; sample.angle = 100; policy.update(sample)
        sample.unlocked = false; policy.update(sample); assert(policy.phase == .locked && policy.sensorDemand == .none)
        sample.unlocked = true; sample.permission = false; policy.update(sample); assert(policy.phase == .permissionRequired && policy.ticket == nil)
        sample.permission = true; sample.available = false; policy.update(sample); assert(policy.phase == .unsupported)
        sample.available = true; sample.reporting = false; policy.update(sample); assert(policy.phase == .notReporting)
        sample.reporting = true; sample.target = nil; policy.update(sample); assert(policy.phase == .unsupported)
        config.maximumBlur = .infinity; policy.configure(config); policy.update(sample); assert(policy.phase == .invalidConfiguration)
        config.maximumBlur = 135
        sample = .init(now: 1000, angle: 100, available: true, reporting: true, permission: true, unlocked: true, target: target)
        var captures = 0, shows = 0, hides = 0
        var demands: [HingeSensorDemand] = []
        var completion: CheckedContinuation<CGImage, Never>?
        let image = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let engine = HingeAnimationEngine(sample: { sample }, capture: { _ in
            captures += 1
            return await withCheckedContinuation { completion = $0 }
        }, show: { _, _, visual in shows += 1; assert(visual.dim >= 0 && visual.dim <= 0.7) }, hide: { hides += 1 }, sensor: { demands.append($0) })
        engine.start(configuration: config); assert(engine.phase == .ready)
        sample.angle = 70; engine.refresh()
        for _ in 0..<10 { await Task.yield() }
        assert(captures == 1 && completion != nil)
        for _ in 0..<10 { engine.refresh() }
        assert(captures == 1) // One pending native request, even if capture ignores cancellation.
        completion!.resume(returning: image); completion = nil
        for _ in 0..<20 { await Task.yield() }
        assert(engine.phase == .active && shows > 0)
        sample.now = 1004; engine.refresh(); assert(engine.phase == .timedOut)
        let oldShows = shows
        sample.now = 1005; sample.angle = 100; engine.refresh(); sample.angle = 60; engine.refresh()
        for _ in 0..<10 { await Task.yield() }
        assert(captures == 2 && completion != nil)
        engine.stop(); engine.start(configuration: config)
        sample.angle = 100; engine.refresh(); sample.angle = 60; engine.refresh()
        assert(captures == 2) // Restart cannot overlap the old uncancellable native request.
        completion!.resume(returning: image); completion = nil
        for _ in 0..<20 { await Task.yield() }
        assert(shows == oldShows && captures == 3 && completion != nil)
        sample.permission = false; engine.refresh()
        completion!.resume(returning: image); completion = nil
        for _ in 0..<20 { await Task.yield() }
        assert(shows == oldShows && engine.phase == .permissionRequired)
        sample.permission = true; sample.angle = 100; engine.refresh(); sample.angle = 60; engine.refresh()
        for _ in 0..<10 { await Task.yield() }
        assert(captures == 4 && completion != nil)
        let oversized = CGContext(data: nil, width: 2049, height: 1, bitsPerComponent: 8, bytesPerRow: 2049 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        completion!.resume(returning: oversized); completion = nil
        for _ in 0..<20 { await Task.yield() }
        assert(engine.phase == .captureFailed && shows == oldShows)
        engine.stop(); engine.interrupt(); assert(engine.phase == .disabled)
        assert(demands.contains(.active) && demands.last == HingeSensorDemand.none && hides > 0)
        var nestedSample = sample; nestedSample.angle = 100; nestedSample.reporting = false
        var nestedEngine: HingeAnimationEngine!
        nestedEngine = HingeAnimationEngine(sample: { nestedSample }, capture: { _ in fatalError("Unexpected capture while open") },
            show: { _, _, _ in fatalError("Unexpected overlay while open") }, hide: {}, sensor: { demand in
                if demand == .standby { nestedSample.reporting = true; nestedEngine.refresh() }
            })
        nestedEngine.start(configuration: config); assert(nestedEngine.phase == .ready); nestedEngine.stop()
        print("Passed production hinge policy/async engine, arming/limits/expiry, permission/lock/sensor/clock failure, stale capture and single-flight cancellation fixtures. Synthetic images only; no desktop capture, overlay, sensor, power setting or physical lid test.")
    }
}

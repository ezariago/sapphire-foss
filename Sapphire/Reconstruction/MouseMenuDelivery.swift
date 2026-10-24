#if !SAPPHIRE_FULL_BUILD
import Foundation

/// A single pending menu lookup. Invalidated/stale requests never execute, and
/// an uncancellable resolver cannot accumulate an unbounded queue of work.
@MainActor
final class MouseMenuDelivery<Selection> {
    private let clock: () -> TimeInterval
    private let validate: (MouseRemapRequest) -> Bool
    private let resolve: (MouseRemapRequest) async -> Selection?
    private let perform: (Selection, MouseRemapRequest) -> Bool
    private let report: (Bool) -> Void
    private let finished: () -> Void
    private var task: Task<Void, Never>?
    private var running = true
    private(set) var busy = false
    init(clock: @escaping () -> TimeInterval, validate: @escaping (MouseRemapRequest) -> Bool,
         resolve: @escaping (MouseRemapRequest) async -> Selection?,
         perform: @escaping (Selection, MouseRemapRequest) -> Bool, report: @escaping (Bool) -> Void, finished: @escaping () -> Void = {}) {
        self.clock = clock; self.validate = validate; self.resolve = resolve; self.perform = perform; self.report = report; self.finished = finished
    }
    func start() { running = true }
    func stop() { running = false; task?.cancel() }
    @discardableResult func submit(_ request: MouseRemapRequest) -> Bool {
        let now = clock()
        guard running, !busy, validate(request), now.isFinite, now >= request.created, now - request.created < 1 else { return false }
        busy = true
        let resolve = resolve
        task = Task { @MainActor [weak self] in
            let selection = await resolve(request)
            guard let self else { return }
            defer { self.busy = false; self.task = nil; self.finished() }
            let now = self.clock()
            guard self.running, !Task.isCancelled, self.validate(request), now.isFinite,
                  now >= request.created, now - request.created < 1 else { return }
            guard let selection else { self.report(false); return }
            self.report(self.perform(selection, request))
        }
        return true
    }
}
#endif

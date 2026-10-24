#if !SAPPHIRE_FULL_BUILD
import AppKit

/// One explicitly requested system region picker; cancellation never targets another process.
private final class RegionCaptureProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func run(output: URL) throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        child.arguments = ["-i", "-s", "-r", "-x", "-t", "png", output.path]
        child.standardInput = FileHandle.nullDevice; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try child.run(); process = child
        }
        // A forgotten region picker must not live indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { [weak self] in self?.cancel() }
        child.waitUntilExit()
        try lock.withLock {
            process = nil
            guard !cancelled, child.terminationStatus == 0 else { throw CancellationError() }
        }
    }
    func cancel() {
        lock.withLock { cancelled = true; if process?.isRunning == true { process?.terminate() } }
    }
}
enum RegionTextCapture {
    static func capture(language: String) async throws -> String {
        let process = RegionCaptureProcess()
        return try await recognizeSelection(language: language, select: process.run, cancel: process.cancel)
    }
    // Shared with isolated image fixtures; production always supplies the system picker above.
    static func recognizeSelection(language: String, select: @escaping @Sendable (URL) throws -> Void,
                                   cancel: @escaping @Sendable () -> Void) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sapphire-RegionText-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("selection.png")
            try select(output)
            try Task.checkCancellation()
            guard let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 64 * 1024 * 1024 else { throw CancellationError() }
            let text = try NativeMediaProcessor.recognizeText(in: output, language: language, useCPUOnly: true)
            try Task.checkCancellation()
            return text
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { cancel(); worker.cancel() })
    }
}
#endif

#if !SAPPHIRE_FULL_BUILD
import AppKit
import Foundation

enum DiskImageInstallError: LocalizedError {
    case commandFailed(String), noApplications, unsafePath, alreadyExists, runningApplication
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): "Disk image operation failed: \(message)"
        case .noApplications: "This image contains no top-level application bundles. Open it with DiskImageMounter to inspect package installers or nested contents."
        case .unsafePath: "The application or destination uses an unsupported path or symbolic link."
        case .alreadyExists: "An application already exists at the destination."
        case .runningApplication: "Quit the installed application before replacing it."
        }
    }
}

struct MountedInstallImage {
    let root: URL
    let device: String
    let applications: [URL]
}

struct DiskImageInstallResult {
    let application: URL
    let backup: URL?
}

enum DiskImageInstaller {
    private static func command(_ arguments: [String]) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sapphire-hdiutil-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stdout")
        let errors = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        let err = try FileHandle(forWritingTo: errors)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            let message = String(data: (try? Data(contentsOf: errors)) ?? Data(), encoding: .utf8) ?? "Unknown error"
            throw DiskImageInstallError.commandFailed(String(message.prefix(2000)))
        }
        return try Data(contentsOf: output)
    }
    static func mount(_ image: URL) throws -> MountedInstallImage {
        guard image.isFileURL, image.pathExtension.lowercased() == "dmg" else { throw DiskImageInstallError.unsafePath }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sapphire-mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var device: String?
        do {
            let data = try command(["attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", "-mountroot", root.path, image.path])
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let entities = plist?["system-entities"] as? [[String: Any]] ?? []
            device = entities.compactMap { $0["dev-entry"] as? String }.first
            guard let device, device.hasPrefix("/dev/disk") else { throw DiskImageInstallError.unsafePath }
            var apps: [URL] = []
            for entity in entities {
                guard let path = entity["mount-point"] as? String else { continue }
                let volume = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                guard volume.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw DiskImageInstallError.unsafePath }
                let children = try FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for child in children where child.pathExtension.lowercased() == "app" {
                    guard try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                    apps.append(child)
                }
            }
            guard !apps.isEmpty else { throw DiskImageInstallError.noApplications }
            return MountedInstallImage(root: root, device: device, applications: apps)
        } catch {
            if let device { _ = try? command(["detach", device]) }
            // Never recursively remove a directory that might still contain a mount.
            if (try? FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: root)
            }
            throw error
        }
    }
    static func unmount(_ image: MountedInstallImage) throws {
        _ = try command(["detach", image.device])
        try FileManager.default.removeItem(at: image.root)
    }
    static func install(_ source: URL, to directory: URL, replace: Bool = false, quarantineSource: URL? = nil) throws -> DiskImageInstallResult {
        let files = FileManager.default
        guard source.isFileURL, directory.isFileURL,
              source.pathExtension.lowercased() == "app",
              try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DiskImageInstallError.unsafePath }
        let sourceID = try AppSecurityValidator.identity(at: source)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let exists = files.fileExists(atPath: destination.path)
        if exists {
            guard replace else { throw DiskImageInstallError.alreadyExists }
            guard try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw DiskImageInstallError.unsafePath }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: sourceID.bundleIdentifier).isEmpty else { throw DiskImageInstallError.runningApplication }
            try AppSecurityValidator.validateReplacement(candidate: source, replacing: destination)
        }
        let stage = directory.appendingPathComponent(".Sapphire-stage-\(UUID().uuidString).app", isDirectory: true)
        defer { try? files.removeItem(at: stage) }
        try files.copyItem(at: source, to: stage)
        if let quarantineSource { QuarantineAttribute.copy(from: [quarantineSource], to: stage, recursively: true) }
        try AppSecurityValidator.validateReplacement(candidate: stage, replacing: source)
        var backup: URL?
        if exists {
            let saved = directory.appendingPathComponent(".Sapphire-backup-\(UUID().uuidString).app", isDirectory: true)
            try files.moveItem(at: destination, to: saved)
            backup = saved
        }
        do { try files.moveItem(at: stage, to: destination) }
        catch {
            if let backup { try? files.moveItem(at: backup, to: destination) }
            throw error
        }
        return DiskImageInstallResult(application: destination, backup: backup)
    }
}
#endif

import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let image = root.appendingPathComponent("Fixture.dmg")
let destination = root.appendingPathComponent("Installed")
let mounted: MountedInstallImage
 do { mounted = try DiskImageInstaller.mount(image) }
 catch DiskImageInstallError.commandFailed(let message) where message.localizedCaseInsensitiveContains("Resource temporarily unavailable") {
    fputs("Transient fixture mount failure: \(message)\n", stderr)
    exit(75)
 }
assert(mounted.applications.count == 1)
assert(mounted.applications[0].lastPathComponent == "Fixture.app")
let result = try DiskImageInstaller.install(mounted.applications[0], to: destination, quarantineSource: image)
assert(result.backup == nil)
let identity = try AppSecurityValidator.identity(at: result.application)
assert(identity.bundleIdentifier == "dev.sapphire.install-fixture")
func rejected(_ work: () throws -> Void) {
    do { try work(); fatalError("Unexpectedly accepted unsafe install") } catch {}
}
rejected { _ = try DiskImageInstaller.install(mounted.applications[0], to: destination) }
let replaced = try DiskImageInstaller.install(mounted.applications[0], to: destination, replace: true)
assert(replaced.backup != nil)
assert(FileManager.default.fileExists(atPath: replaced.backup!.path))
let tampered = root.appendingPathComponent("Tampered.app")
try FileManager.default.copyItem(at: mounted.applications[0], to: tampered)
try Data("tampered".utf8).write(to: tampered.appendingPathComponent("Contents/Resources/fixture.txt"))
rejected { _ = try DiskImageInstaller.install(tampered, to: destination, replace: true) }
let stillValid = try AppSecurityValidator.identity(at: replaced.application)
assert(stillValid == identity)
let symlink = root.appendingPathComponent("Symlink.app")
try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: mounted.applications[0])
rejected { _ = try DiskImageInstaller.install(symlink, to: destination) }
try DiskImageInstaller.unmount(mounted)
assert(!FileManager.default.fileExists(atPath: mounted.root.path))
print("Passed real DMG read-only mount, signed staging/install, replacement backup, tamper/symlink rejection and detach checks.")

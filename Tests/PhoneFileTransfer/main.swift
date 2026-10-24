import Foundation
import CryptoKit
import Darwin

func rejected(_ work: () throws -> Void) { do { try work(); fatalError("Expected refusal") } catch { } }
func reply(_ id: String, _ state: String, _ next: Int, _ bytes: Int) -> [String: PhoneJSON] {
    ["requestId": .string(id), "state": .string(state), "nextIndex": .number(Double(next)), "receivedBytes": .number(Double(bytes))]
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("SapphireFileTransfer-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
for name in ["../escape", "a/b", "a\\b", "..", " ", "bad\nname", "hidden\u{202e}exe"] { assert(!PhoneFileTransferPolicy.validName(name)) }
assert(PhoneFileTransferPolicy.validName("Fixture photo 📷.png"))
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: 0, now: 0) == 45)
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: 0, now: 590) == 10)
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: 0, now: 600) == nil)
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: 10, now: 9) == nil)
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: .nan, now: 0) == nil)
assert(PhoneFileTransferPolicy.phaseBudget(startedAt: 0, now: .infinity) == nil)
let source = root.appendingPathComponent("Synthetic sample.bin")
let data = Data((0..<4097).map { UInt8($0 % 251) })
try data.write(to: source)
let prepared = try PhoneFileTransferPolicy.read(source)
assert(prepared.data == data && prepared.name == source.lastPathComponent)
let link = root.appendingPathComponent("link.bin")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
rejected { _ = try PhoneFileTransferPolicy.read(link) }
rejected { _ = try PhoneFileTransferPolicy.read(root) }
rejected { _ = try PhoneFileTransferPolicy.read(URL(string: "https://example.com/file")!) }
let large = root.appendingPathComponent("large.bin")
FileManager.default.createFile(atPath: large.path, contents: nil)
let largeFile = try FileHandle(forWritingTo: large); try largeFile.truncate(atOffset: UInt64(PhoneFileTransferPolicy.maxBytes + 1)); try largeFile.close()
rejected { _ = try PhoneFileTransferPolicy.read(large) }
let boundaryFile = try FileHandle(forWritingTo: large)
try boundaryFile.truncate(atOffset: UInt64(PhoneFileTransferPolicy.maxBytes)); try boundaryFile.close()
let boundary = try PhoneFileTransferPolicy.read(large)
assert(boundary.data.count == PhoneFileTransferPolicy.maxBytes)
var atLimit = OutgoingPhoneFileTransfer(file: boundary)
var limitStep = atLimit.accept(reply(atLimit.id, "ready", 0, 0))
var limitIndex = 0
while case .send(let packet) = limitStep {
    if packet.type == "file.finish" { break }
    limitIndex += 1
    limitStep = atLimit.accept(reply(atLimit.id, "chunk", limitIndex, min(limitIndex * PhoneFileTransferPolicy.chunkBytes, boundary.data.count)))
}
assert(limitIndex == PhoneFileTransferPolicy.maxBytes / PhoneFileTransferPolicy.chunkBytes)
if case .complete = atLimit.accept(reply(atLimit.id, "complete", limitIndex, boundary.data.count)) { } else { fatalError("Exact-limit completion") }
let fifo = root.appendingPathComponent("pipe.bin")
assert(mkfifo(fifo.path, 0o600) == 0)
rejected { _ = try PhoneFileTransferPolicy.read(fifo) } // Must not block opening a FIFO.
var transfer = OutgoingPhoneFileTransfer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, file: prepared)
var packets: [[String: PhoneJSON]] = [["type": .string(transfer.offer.type), "payload": .object(transfer.offer.payload)]]
var transition = transfer.accept(reply(transfer.id, "ready", 0, 0))
var all = Data(); var index = 0
while case .send(let packet) = transition {
    packets.append(["type": .string(packet.type), "payload": .object(packet.payload)])
    if packet.type == "file.finish" { break }
    assert(packet.type == "file.chunk" && packet.payload["index"]?.int == index)
    let bytes = Data(base64Encoded: packet.payload["data"]!.string!)!
    assert(bytes.count <= PhoneFileTransferPolicy.chunkBytes)
    all.append(bytes); index += 1
    transition = transfer.accept(reply(transfer.id, "chunk", index, all.count))
}
assert(all == data && index == 3 && transfer.acknowledgedBytes == data.count)
if case .complete = transfer.accept(reply(transfer.id, "complete", index, data.count)) { } else { fatalError("No completion") }
if case .ignored = transfer.accept(reply(transfer.id, "complete", index, data.count)) { } else { fatalError("Duplicate completion") }
for invalid in [reply(transfer.id, "chunk", 1, 2048), reply(transfer.id, "ready", 1, 0), reply(transfer.id, "ready", 0, -1), reply(transfer.id, "ready", Int.max, 0)] {
    var candidate = OutgoingPhoneFileTransfer(id: UUID(uuidString: transfer.id)!, file: prepared)
    if case .failed = candidate.accept(invalid) { } else { fatalError("Invalid acknowledgement accepted") }
}
for key in ["nextIndex", "receivedBytes"] {
    var invalid = reply(transfer.id, "ready", 0, 0); invalid[key] = .number(0.5)
    var candidate = OutgoingPhoneFileTransfer(id: UUID(uuidString: transfer.id)!, file: prepared)
    if case .failed = candidate.accept(invalid) { } else { fatalError("Fractional acknowledgement") }
}
var empty = OutgoingPhoneFileTransfer(file: .init(name: "Empty", data: Data()))
if case .send(let finish) = empty.accept(reply(empty.id, "ready", 0, 0)) { assert(finish.type == "file.finish") } else { fatalError("Empty handling") }
if case .complete = empty.accept(reply(empty.id, "complete", 0, 0)) { } else { fatalError("Empty completion") }
var disabled = OutgoingPhoneFileTransfer(file: prepared)
if case .ignored = disabled.accept(reply(UUID().uuidString, "ready", 0, 0)) { } else { fatalError("Wrong request") }
if case .failed = disabled.accept(reply(disabled.id, "disabled", 0, 0)) { } else { fatalError("Disabled state") }
for type in ["file.offer", "file.chunk", "file.finish", "file.cancel", "file.transfer.result"] { assert(!PhoneHandshakePolicy.acceptsPlaintext(type: type, isSecure: false)) }
if CommandLine.arguments.count > 1 {
    try JSONEncoder().encode(packets).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Passed bounded regular-file/symlink/FIFO/source snapshot, filename, chunk/ACK/progress/order, empty-file and plaintext-rejection fixtures. Files are synthetic temporary data only.")

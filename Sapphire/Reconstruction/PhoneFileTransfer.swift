#if !SAPPHIRE_FULL_BUILD
import Foundation
import CryptoKit
import Darwin

enum PhoneFileTransferPolicy {
    static let maxBytes = 5 * 1024 * 1024
    static let chunkBytes = 2048
    static func phaseBudget(startedAt: TimeInterval, now: TimeInterval) -> TimeInterval? {
        guard startedAt.isFinite, startedAt >= 0, now.isFinite, now >= startedAt, now - startedAt < 600 else { return nil }
        return min(45, 600 - (now - startedAt))
    }
    static func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 180,
              !name.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            ![Unicode.GeneralCategory.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
                && scalar != "/" && scalar != "\\"
        }
    }
    static func integer(_ value: PhoneJSON?) -> Int? {
        guard case .number(let number) = value, number.isFinite, number >= 0,
              number < Double(Int.max), number.rounded(.towardZero) == number else { return nil }
        return Int(number)
    }
    struct Prepared: Sendable {
        let name: String
        let data: Data
        let sha256: String
        init(name: String, data: Data) {
            self.name = name; self.data = data
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
    enum ReadError: LocalizedError {
        case unsupported, invalidName, tooLarge, changed, unreadable
        var errorDescription: String? {
            switch self {
            case .unsupported: "Choose one ordinary local file; symbolic links, folders and special files are not supported."
            case .invalidName: "Rename the file to a name up to 180 UTF-8 bytes without separators or control characters."
            case .tooLarge: "Bluetooth file transfer supports one file up to 5 MiB."
            case .changed: "The file changed while being read. Save it and try again."
            case .unreadable: "The selected file could not be read. Check its permissions and availability."
            }
        }
    }
    static func read(_ url: URL) throws -> Prepared {
        guard !Task.isCancelled else { throw CancellationError() }
        guard url.isFileURL, url.host == nil || url.host == "localhost", !url.path.utf8.contains(0) else { throw ReadError.unsupported }
        guard validName(url.lastPathComponent) else { throw ReadError.invalidName }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw ReadError.unreadable }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG) else { throw ReadError.unsupported }
        guard before.st_size >= 0, before.st_size <= maxBytes else { throw ReadError.tooLarge }
        var data = Data()
        while data.count < before.st_size {
            guard !Task.isCancelled else { throw CancellationError() }
            guard let bytes = try file.read(upToCount: min(64 * 1024, Int(before.st_size) - data.count)), !bytes.isEmpty else { throw ReadError.changed }
            data.append(bytes)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw ReadError.changed }
        return .init(name: url.lastPathComponent, data: data)
    }
}

/// A cancelled slow filesystem read cannot spawn parallel preparation readers.
actor PhoneFilePreparer {
    func prepare(_ url: URL) throws -> PhoneFileTransferPolicy.Prepared { try PhoneFileTransferPolicy.read(url) }
}

struct OutgoingPhoneFileTransfer: Sendable {
    struct Packet: Sendable {
        let type: String
        let payload: [String: PhoneJSON]
    }
    enum Transition { case ignored, send(Packet), complete, failed(String) }
    private enum Phase { case offer, chunk(Int), finish, ended }
    let id: String
    let file: PhoneFileTransferPolicy.Prepared
    private var phase = Phase.offer
    private(set) var acknowledgedBytes = 0
    init(id: UUID = UUID(), file: PhoneFileTransferPolicy.Prepared) {
        self.id = id.uuidString; self.file = file
    }
    var offer: Packet { .init(type: "file.offer", payload: ["requestId": .string(id), "name": .string(file.name), "size": .number(Double(file.data.count)), "sha256": .string(file.sha256)]) }
    var progress: Double { file.data.isEmpty ? 0 : Double(acknowledgedBytes) / Double(file.data.count) }
    mutating func accept(_ payload: [String: PhoneJSON]) -> Transition {
        guard payload["requestId"]?.string == id else { return .ignored }
        if case .ended = phase { return .ignored }
        let state = payload["state"]?.string ?? ""
        let failures = ["disabled": "Enable Receive files from paired Mac in Sapphire Companion.",
                        "busy": "Save or discard the phone's previous staged file, or finish its current transfer first.",
                        "expired": "The phone transfer expired. Prepare a new transfer if needed.",
                        "invalid": "The phone rejected the file request.",
                        "error": "The phone could not stage or verify this file. Check its storage and connection.",
                        "cancelled": "The phone cancelled the partial transfer."]
        if let message = failures[state] { phase = .ended; return .failed(message) }
        guard let next = PhoneFileTransferPolicy.integer(payload["nextIndex"]), let bytes = PhoneFileTransferPolicy.integer(payload["receivedBytes"]),
              next >= 0, next <= (PhoneFileTransferPolicy.maxBytes / PhoneFileTransferPolicy.chunkBytes),
              bytes >= 0, bytes <= file.data.count else { return fail() }
        switch phase {
        case .offer:
            guard state == "ready", next == 0, bytes == 0 else { return fail() }
            return nextPacket(index: 0)
        case .chunk(let index):
            let expected = min((index + 1) * PhoneFileTransferPolicy.chunkBytes, file.data.count)
            guard state == "chunk", next == index + 1, bytes == expected else { return fail() }
            acknowledgedBytes = bytes
            return nextPacket(index: next)
        case .finish:
            let expectedIndex = (file.data.count + PhoneFileTransferPolicy.chunkBytes - 1) / PhoneFileTransferPolicy.chunkBytes
            guard state == "complete", bytes == file.data.count, next == expectedIndex else { return fail() }
            acknowledgedBytes = bytes; phase = .ended
            return .complete
        case .ended: return .ignored
        }
    }
    private mutating func fail() -> Transition { phase = .ended; return .failed("Invalid or out-of-order file acknowledgement. Transfer stopped.") }
    private mutating func nextPacket(index: Int) -> Transition {
        let offset = index * PhoneFileTransferPolicy.chunkBytes
        if offset >= file.data.count {
            phase = .finish
            return .send(.init(type: "file.finish", payload: ["requestId": .string(id)]))
        }
        let bytes = file.data.subdata(in: offset..<min(file.data.count, offset + PhoneFileTransferPolicy.chunkBytes))
        phase = .chunk(index)
        return .send(.init(type: "file.chunk", payload: ["requestId": .string(id), "index": .number(Double(index)), "data": .string(bytes.base64EncodedString())]))
    }
}
#endif

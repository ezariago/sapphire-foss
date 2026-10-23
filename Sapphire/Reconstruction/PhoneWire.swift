// Independently reconstructed from the Android companion's wire format.
// This is replacement source, not recovered original Swift source.
import Foundation
import CryptoKit

enum PhoneWireError: Error, LocalizedError {
    case malformed, oversized, unauthenticated, replay, expired
    var errorDescription: String? {
        switch self {
        case .malformed: "The phone sent an invalid message."
        case .oversized: "The phone message exceeded the supported size."
        case .unauthenticated: "The phone connection could not be authenticated."
        case .replay: "A repeated phone message was rejected."
        case .expired: "Pairing expired. Show a new code and try again."
        }
    }
}

enum PhoneHandshakePolicy {
    // Android also sends hid.prefs/status/media requests during its hello.
    // Ignore those until authentication; they must not terminate QR pairing.
    static func acceptsPlaintext(type: String, isSecure: Bool) -> Bool {
        !isSecure && ["hello", "pair.hello", "pair.confirm", "pair.result", "pair.classicStart"].contains(type)
    }
}

enum PhoneJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: PhoneJSON]), array([PhoneJSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: PhoneJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([PhoneJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var int: Int? {
        guard case .number(let v) = self, v.isFinite,
              v >= Double(Int.min), v < Double(Int.max) else { return nil }
        return Int(v)
    }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var object: [String: PhoneJSON]? { if case .object(let v) = self { v } else { nil } }
}

struct PhoneEnvelope: Codable, Sendable {
    var v: Int = 1
    var id: String = UUID().uuidString
    var type: String
    var ts: String = ISO8601DateFormatter().string(from: Date())
    var counter: Int64 = 0
    var payload: [String: PhoneJSON] = [:]

    enum CodingKeys: String, CodingKey { case v, id, type, ts, counter, payload }
    init(type: String, counter: Int64 = 0, payload: [String: PhoneJSON] = [:]) {
        self.type = type; self.counter = counter; self.payload = payload
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try c.decode(String.self, forKey: .type)
        ts = try c.decodeIfPresent(String.self, forKey: .ts) ?? ""
        counter = try c.decodeIfPresent(Int64.self, forKey: .counter) ?? 0
        payload = try c.decodeIfPresent([String: PhoneJSON].self, forKey: .payload) ?? [:]
    }
}

struct PhoneAdvertisement: Equatable {
    let handle: Data
    let capabilities: UInt16
    let batteryPercent: Int?
    let isPairing: Bool?
    // CoreBluetooth includes the two-byte company ID; Android does not.
    init?(manufacturerData data: Data) {
        let b = Array(data)
        guard b.count >= 15, b[0] == 0xff, b[1] == 0xff,
              b[2] == 1, b[3] == 1 else { return nil }
        handle = Data(b[4..<12])
        capabilities = UInt16(b[12]) | UInt16(b[13]) << 8
        batteryPercent = b[14] <= 100 ? Int(b[14]) : nil
        isPairing = b.count > 15 ? b[15] & 1 != 0 : nil
    }
    func matches(deviceID: String) -> Bool {
        handle == Data(SHA256.hash(data: Data(deviceID.utf8)).prefix(8))
    }
}

enum PhoneDiscoveryPolicy {
    static func isKnownPhone(savedDeviceID: String, savedPeripheralID: UUID,
                             candidateID: UUID, advertisement: PhoneAdvertisement?) -> Bool {
        candidateID == savedPeripheralID || advertisement?.matches(deviceID: savedDeviceID) == true
    }
}

struct PhoneGATTFraming {
    private struct Partial { var data: Data; let started: Date }
    private var partials: [UInt16: Partial] = [:]
    static let maximumBytes = 16_384

    static func chunks(_ data: Data, id: UInt16, maximumWrite: Int) throws -> [Data] {
        guard data.count <= maximumBytes else { throw PhoneWireError.oversized }
        guard maximumWrite >= 4 else { throw PhoneWireError.malformed }
        let capacity = min(maximumWrite, 512) - 3
        if data.isEmpty { return [Data([3, UInt8(id & 255), UInt8(id >> 8)])] }
        var result: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + capacity)
            let flags: UInt8 = (offset == 0 ? 1 : 0) | (end == data.count ? 2 : 0)
            result.append(Data([flags, UInt8(id & 255), UInt8(id >> 8)]) + data.subdata(in: offset..<end))
            offset = end
        }
        return result
    }

    mutating func receive(_ chunk: Data, now: Date = Date()) throws -> Data? {
        partials = partials.filter { now.timeIntervalSince($0.value.started) < 15 }
        let b = Array(chunk)
        guard b.count >= 3, b[0] & ~3 == 0 else { throw PhoneWireError.malformed }
        let id = UInt16(b[1]) | UInt16(b[2]) << 8
        if b[0] & 1 != 0 {
            guard partials[id] != nil || partials.count < 16 else { throw PhoneWireError.oversized }
            partials[id] = Partial(data: Data(), started: now)
        }
        guard var part = partials[id] else { throw PhoneWireError.malformed }
        part.data.append(contentsOf: b.dropFirst(3))
        guard part.data.count <= Self.maximumBytes else {
            partials.removeValue(forKey: id)
            throw PhoneWireError.oversized
        }
        if b[0] & 2 != 0 {
            partials.removeValue(forKey: id)
            return part.data
        }
        partials[id] = part
        return nil
    }
}

struct PhonePairingSecrets {
    let linkKey: Data
    let sas: String
}

struct PhonePairingSession {
    let key: P256.KeyAgreement.PrivateKey
    let nonce: Data
    let expiresAt: Date

    init(now: Date = Date(), key: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey(), nonce: Data? = nil) {
        self.key = key
        self.nonce = nonce ?? Self.randomBytes(16)
        expiresAt = now.addingTimeInterval(180)
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    func qr(macID: String, name: String) throws -> String {
        // The current BLE-only replacement does not advertise a TLS/Wi-Fi endpoint.
        // The required legacy SPKI field is empty; no fabricated certificate pin.
        let payload: [String: PhoneJSON] = [
            "v": .number(1), "macDeviceId": .string(macID), "macName": .string(name),
            "ecdhPublicKey": .string(key.publicKey.x963Representation.base64EncodedString()),
            "nonce": .string(nonce.base64EncodedString()), "spkiSha256": .string("")
        ]
        return try JSONEncoder().encode(payload).base64EncodedString()
    }

    func derive(publicKey: Data, phoneNonce: Data, now: Date = Date()) throws -> PhonePairingSecrets {
        guard now < expiresAt else { throw PhoneWireError.expired }
        guard nonce.count == 16, phoneNonce.count == 16 else { throw PhoneWireError.malformed }
        let remote = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
        let secret = try key.sharedSecretFromKeyAgreement(with: remote)
        let salt = nonce + phoneNonce
        let linkKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: Data("sapphire-continuity-link".utf8), outputByteCount: 32)
        let code = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: Data("sapphire-continuity-sas".utf8), outputByteCount: 8)
        let value = code.withUnsafeBytes { $0.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        return PhonePairingSecrets(linkKey: linkKey.withUnsafeBytes { Data($0) },
                                   sas: String(format: "%06u", value % 1_000_000))
    }
}

struct PhoneBLESession {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var outgoing: UInt64 = 0
    private var highestIncoming: UInt64 = 0
    private var seen: Set<UInt64> = []
    private static let magic = Data("SBE1".utf8)

    init(linkKey: Data, macNonce: Data, phoneNonce: Data, isMac: Bool = true) throws {
        guard linkKey.count == 32, macNonce.count == 32, phoneNonce.count == 32 else {
            throw PhoneWireError.malformed
        }
        let key = SymmetricKey(data: linkKey), salt = macNonce + phoneNonce
        let m2p = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt,
            info: Data("sapphire.ble.mac-to-phone.v1".utf8), outputByteCount: 32)
        let p2m = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt,
            info: Data("sapphire.ble.phone-to-mac.v1".utf8), outputByteCount: 32)
        sendKey = isMac ? m2p : p2m
        receiveKey = isMac ? p2m : m2p
    }

    private static func counterBytes(_ value: UInt64) -> Data {
        Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    mutating func seal(_ message: Data) throws -> Data {
        guard outgoing < UInt64(Int64.max), message.count <= PhoneGATTFraming.maximumBytes - 28 else {
            throw PhoneWireError.oversized
        }
        outgoing += 1
        let count = Self.counterBytes(outgoing), header = Self.magic + count
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + count)
        let box = try ChaChaPoly.seal(message, using: sendKey, nonce: nonce, authenticating: header)
        return header + box.ciphertext + box.tag
    }

    mutating func open(_ frame: Data) throws -> Data {
        guard frame.count >= 28, frame.count <= PhoneGATTFraming.maximumBytes,
              frame.prefix(4) == Self.magic else { throw PhoneWireError.malformed }
        let bytes = frame.subdata(in: 4..<12)
        let counter = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard counter > 0, counter <= UInt64(Int64.max), !seen.contains(counter),
              counter > highestIncoming || highestIncoming - counter <= 256 else { throw PhoneWireError.replay }
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + bytes)
        let box = try ChaChaPoly.SealedBox(nonce: nonce,
            ciphertext: frame.subdata(in: 12..<(frame.count - 16)), tag: frame.suffix(16))
        let message = try ChaChaPoly.open(box, using: receiveKey, authenticating: frame.prefix(12))
        highestIncoming = max(counter, highestIncoming)
        seen.insert(counter)
        seen = seen.filter { highestIncoming - $0 <= 256 }
        return message
    }
}


// The installed Android companion implements WPA2 local-only hotspot credentials.
// Validate them before any operating-system network change.
struct PhoneHotspotCredentials: Sendable {
    let ssid: String
    let passphrase: String
    init(payload: [String: PhoneJSON]) throws {
        guard let ssid = payload["ssid"]?.string, (1...32).contains(ssid.utf8.count),
              !ssid.contains("\0"), let passphrase = payload["passphrase"]?.string,
              (8...63).contains(passphrase.utf8.count), !passphrase.contains("\0"),
              payload["security"]?.string?.lowercased() == "wpa2" else { throw PhoneWireError.malformed }
        self.ssid = ssid; self.passphrase = passphrase
    }
}

struct PhoneClipboardChanges {
    private var lastChange: Int
    init(baseline: Int) { lastChange = baseline }
    mutating func skip(through change: Int) { lastChange = change }
    mutating func consume(change: Int, text: String?, blocked: Bool) -> String? {
        guard change != lastChange else { return nil }
        lastChange = change // Never queue private, unsupported or offline copies for later.
        guard !blocked, let text, !text.isEmpty, text.utf8.count < 12_000 else { return nil }
        return text
    }
}


/// Authenticated device summaries. Missing/invalid radio values remain unknown.
struct PhoneDeviceStatus: Equatable {
    var signalLevel: Int?
    var carrier: String?
    var charging = false
    var network: String?

    init() {}
    init(payload: [String: PhoneJSON]) {
        if case .number(let value) = payload["signalLevel"], value.isFinite,
           value.rounded() == value, (0...4).contains(value) { signalLevel = Int(value) }
        let name = payload["carrier"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty, name.count <= 80,
           !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { carrier = name }
        charging = payload["charging"]?.bool ?? false
        if let value = payload["network"]?.string, ["wifi", "cellular", "none"].contains(value) { network = value }
    }
}

/// Explicit web-link handoff only. Never accepts executable/custom/file URLs.
enum PhoneHandoffURL {
    static func parse(_ input: String) -> URL? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.utf8.count <= 4096,
              raw.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
              !raw.contains("\\"),
              let parts = URLComponents(string: raw),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              let host = parts.host, !host.isEmpty,
              parts.port.map({ (0...65535).contains($0) }) ?? true,
              let url = parts.url else { return nil }
        return url
    }
}

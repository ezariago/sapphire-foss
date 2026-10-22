import Foundation
import CryptoKit

var checks = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw NSError(domain: name, code: 1) }
    checks += 1
}
func rejects(_ name: String, _ body: () throws -> Void) throws {
    do { try body() } catch { checks += 1; return }
    throw NSError(domain: "Expected rejection: \(name)", code: 1)
}
func sequence(_ start: Int, _ count: Int) -> Data { Data((start..<(start + count)).map(UInt8.init)) }
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixtureURL))
let scalar1 = Data(repeating: 0, count: 31) + Data([1])
let scalar2 = Data(repeating: 0, count: 31) + Data([2])
let macKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: scalar1)
let phoneKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: scalar2)
let now = Date()
let pairing = PhonePairingSession(now: now, key: macKey, nonce: sequence(0, 16))
let result = try pairing.derive(publicKey: phoneKey.publicKey.x963Representation, phoneNonce: sequence(16, 16))
try expect(result.linkKey.base64EncodedString() == fixture["linkKey"], "Java/CryptoKit ECDH and HKDF agree")
try expect(result.sas == fixture["sas"], "Java/CryptoKit SAS agrees")
try rejects("expired pairing") { _ = try pairing.derive(publicKey: phoneKey.publicKey.x963Representation,
    phoneNonce: sequence(16, 16), now: now.addingTimeInterval(181)) }
try rejects("invalid EC point") { _ = try pairing.derive(publicKey: Data(repeating: 0, count: 65), phoneNonce: sequence(16, 16)) }
try rejects("invalid pairing nonce") { _ = try pairing.derive(publicKey: phoneKey.publicKey.x963Representation, phoneNonce: Data([0])) }
let qr = try pairing.qr(macID: "fixture-mac", name: "Fixture")
let qrObject = try JSONDecoder().decode([String: PhoneJSON].self, from: Data(base64Encoded: qr)!)
try expect(qrObject["ecdhPublicKey"]?.string == macKey.publicKey.x963Representation.base64EncodedString(), "QR public key")
try expect(qrObject["nonce"]?.string == sequence(0, 16).base64EncodedString(), "QR nonce")

var mac = try PhoneBLESession(linkKey: result.linkKey, macNonce: sequence(0, 32), phoneNonce: sequence(32, 32))
var phone = try PhoneBLESession(linkKey: result.linkKey, macNonce: sequence(0, 32), phoneNonce: sequence(32, 32), isMac: false)
let plaintext = Data("{\"type\":\"status.request\"}".utf8)
let frame = try mac.seal(plaintext)
try expect(frame.base64EncodedString() == fixture["frame"], "Java/CryptoKit ChaCha20 frame agrees byte for byte")
try expect(try phone.open(frame) == plaintext, "Mac to phone direction")
try rejects("replay") { _ = try phone.open(frame) }
let reply = try phone.seal(Data("phone reply".utf8))
try expect(try mac.open(reply) == Data("phone reply".utf8), "Phone to Mac direction")
let validAfterTamper = try phone.seal(Data("must authenticate".utf8))
var tampered = validAfterTamper
tampered[tampered.count - 1] ^= 1
try rejects("modified authentication tag") { _ = try mac.open(tampered) }
try expect(try mac.open(validAfterTamper) == Data("must authenticate".utf8), "Failed authentication does not poison replay state")
var stranger = try PhoneBLESession(linkKey: Data(repeating: 7, count: 32), macNonce: sequence(0, 32), phoneNonce: sequence(32, 32))
try rejects("wrong pairing key") { _ = try stranger.open(reply) }
try rejects("invalid encryption nonce length") { _ = try PhoneBLESession(linkKey: result.linkKey, macNonce: Data(), phoneNonce: sequence(32, 32)) }
var reorderedPhone = try PhoneBLESession(linkKey: result.linkKey, macNonce: sequence(0, 32), phoneNonce: sequence(32, 32), isMac: false)
var reorderedMac = try PhoneBLESession(linkKey: result.linkKey, macNonce: sequence(0, 32), phoneNonce: sequence(32, 32))
let early = try reorderedPhone.seal(Data([1]))
let later = try reorderedPhone.seal(Data([2]))
try expect(try reorderedMac.open(later) == Data([2]), "Later authenticated frame accepted")
try expect(try reorderedMac.open(early) == Data([1]), "Out-of-order frame in replay window accepted once")
let unseenOldFrame = try reorderedPhone.seal(Data([4]))
var tooOld = early
for _ in 0..<257 { tooOld = try reorderedPhone.seal(Data([3])) }
try expect(try reorderedMac.open(tooOld) == Data([3]), "Replay window advances on authentication")
try rejects("unseen stale replay-window frame") { _ = try reorderedMac.open(unseenOldFrame) }

let bytes = sequence(0, 256)
for size in [20, 185, 512] {
    var parser = PhoneGATTFraming()
    let chunks = try PhoneGATTFraming.chunks(bytes, id: 0xbeef, maximumWrite: size)
    var output: Data?
    for chunk in chunks { if let value = try parser.receive(chunk) { output = value } }
    try expect(output == bytes, "GATT reassembly at write limit \(size)")
}
var parser = PhoneGATTFraming()
try rejects("orphan fragment") { _ = try parser.receive(Data([2, 1, 0, 9])) }
try rejects("invalid fragment flags") { _ = try parser.receive(Data([7, 1, 0])) }
try rejects("oversized outgoing message") { _ = try PhoneGATTFraming.chunks(Data(repeating: 0, count: 16385), id: 1, maximumWrite: 20) }
try rejects("invalid write size") { _ = try PhoneGATTFraming.chunks(bytes, id: 1, maximumWrite: 3) }
let fragments = try PhoneGATTFraming.chunks(bytes, id: 2, maximumWrite: 185)
_ = try parser.receive(fragments[0], now: now)
try rejects("expired partial") { _ = try parser.receive(fragments[1], now: now.addingTimeInterval(16)) }
let id = "fixture-phone"
let adData = Data([255, 255, 1, 1]) + Data(SHA256.hash(data: Data(id.utf8)).prefix(8)) + Data([15, 0, 80, 1])
let ad = PhoneAdvertisement(manufacturerData: adData)!
try expect(ad.matches(deviceID: id) && !ad.matches(deviceID: "another-phone"), "Advertisement identity handle")
try expect(ad.batteryPercent == 80 && ad.isPairing == true && ad.capabilities == 15, "Advertisement fields")
try expect(PhoneAdvertisement(manufacturerData: adData.dropLast())?.isPairing == nil, "Legacy advertisement")
try expect(PhoneAdvertisement(manufacturerData: Data([0, 0]) + adData.dropFirst(2)) == nil, "Other manufacturer rejected")
try expect(PhoneAdvertisement(manufacturerData: Data([255, 255, 1])) == nil, "Short advertisement rejected")
let oldPeripheral = UUID(), rotatedPeripheral = UUID()
try expect(PhoneDiscoveryPolicy.isKnownPhone(savedDeviceID: id, savedPeripheralID: oldPeripheral,
    candidateID: rotatedPeripheral, advertisement: ad), "Paired phone recognized after BLE address rotation")
try expect(!PhoneDiscoveryPolicy.isKnownPhone(savedDeviceID: "unrelated-phone", savedPeripheralID: oldPeripheral,
    candidateID: rotatedPeripheral, advertisement: ad), "Different phone with a new address is rejected")
try expect(PhoneDiscoveryPolicy.isKnownPhone(savedDeviceID: id, savedPeripheralID: oldPeripheral,
    candidateID: oldPeripheral, advertisement: nil), "Existing discovered peripheral is eligible for authentication")
let envelope = PhoneEnvelope(type: "status.request")
try expect(try JSONDecoder().decode(PhoneEnvelope.self, from: JSONEncoder().encode(envelope)).type == "status.request", "Envelope serialization")
let minimal = try JSONDecoder().decode(PhoneEnvelope.self, from: Data("{\"type\":\"ping\"}".utf8))
try expect(minimal.v == 1 && minimal.counter == 0 && minimal.payload.isEmpty, "Android optional envelope fields")
try expect(PhoneHandshakePolicy.acceptsPlaintext(type: "hello", isSecure: false), "Pre-auth hello is allowed")
try expect(!PhoneHandshakePolicy.acceptsPlaintext(type: "hid.prefs", isSecure: false), "Pre-auth setup messages are ignored")
try expect(!PhoneHandshakePolicy.acceptsPlaintext(type: "clipboard.update", isSecure: false), "Unauthenticated clipboard is ignored")
try expect(!PhoneHandshakePolicy.acceptsPlaintext(type: "hello", isSecure: true), "No plaintext messages in established session")
let repeatedPairing = try pairing.derive(publicKey: phoneKey.publicKey.x963Representation, phoneNonce: sequence(16, 16))
try expect(repeatedPairing.linkKey == result.linkKey && repeatedPairing.sas == result.sas, "Identical pairing retries preserve key and code")
var clipboard = PhoneClipboardChanges(baseline: 10)
try expect(clipboard.consume(change: 10, text: "old clipboard", blocked: false) == nil, "Connection does not send stale clipboard")
try expect(clipboard.consume(change: 11, text: "new text", blocked: false) == "new text", "New clipboard change is sent")
try expect(clipboard.consume(change: 11, text: "new text", blocked: false) == nil, "Polling cannot resend an unchanged clipboard")
try expect(clipboard.consume(change: 12, text: "private", blocked: true) == nil, "Marked clipboard items are skipped")
try expect(clipboard.consume(change: 12, text: "private", blocked: false) == nil, "Skipped private items are not queued")
clipboard.skip(through: 13)
try expect(clipboard.consume(change: 13, text: "received from phone", blocked: false) == nil, "Copying phone text does not echo")
try expect(clipboard.consume(change: 14, text: String(repeating: "é", count: 6000), blocked: false) == nil, "Clipboard limit counts UTF-8 bytes")
try expect(clipboard.consume(change: 15, text: "", blocked: false) == nil, "Empty clipboard is skipped")
try expect(clipboard.consume(change: 1, text: "after pasteboard restart", blocked: false) != nil, "Clipboard survives pasteboard counter reset")
let hotspotPayload: [String: PhoneJSON] = ["ssid": .string("Android-test"), "passphrase": .string("test-only-passphrase"), "band": .string("2.4"), "security": .string("wpa2")]
try expect(try PhoneHotspotCredentials(payload: hotspotPayload).ssid == "Android-test", "Android hotspot credential fields decode")
for (field, invalid) in [("ssid", ""), ("ssid", String(repeating: "é", count: 17)), ("passphrase", "short"), ("security", "open"), ("ssid", "bad\0ssid")] {
    var bad = hotspotPayload; bad[field] = .string(invalid)
    try rejects("Invalid hotspot field: \(field)") { _ = try PhoneHotspotCredentials(payload: bad) }
}
try expect(!PhoneHandshakePolicy.acceptsPlaintext(type: "hotspot.credentials", isSecure: false), "Unauthenticated Wi-Fi credentials cannot change networks")
let deviceStatus = PhoneDeviceStatus(payload: ["signalLevel": .number(3), "carrier": .string("  Telkomsel  "), "charging": .bool(true), "network": .string("cellular")])
try expect(deviceStatus.signalLevel == 3 && deviceStatus.carrier == "Telkomsel" && deviceStatus.charging && deviceStatus.network == "cellular", "Authenticated phone telemetry fields decode")
try expect(PhoneDeviceStatus(payload: [:]).signalLevel == nil, "Legacy phone without signal data stays unknown")
try expect(PhoneDeviceStatus(payload: ["signalLevel": .number(0)]).signalLevel == 0, "Zero signal is distinct from unavailable signal")
for invalid in [-1.0, 5.0, 2.5, Double.infinity] {
    try expect(PhoneDeviceStatus(payload: ["signalLevel": .number(invalid)]).signalLevel == nil, "Invalid signal level rejected")
}
try expect(PhoneDeviceStatus(payload: ["carrier": .string("bad\ncarrier"), "network": .string("unexpected")]).carrier == nil, "Control characters cannot enter carrier UI")
try expect(PhoneDeviceStatus(payload: ["network": .string("unexpected")]).network == nil, "Unknown network kind stays unavailable")
func notificationPayload(key: String = "test-key", revision: String = "v1", snapshot: Bool = false) -> [String: PhoneJSON] {
    ["key": .string(key), "revision": .string(revision), "appId": .string("test.app"),
     "appName": .string("Test app"), "title": .string("Test notification"), "text": .string("Hello 🔔"),
     "clearable": .bool(true), "snapshot": .bool(snapshot),
     "actions": .array([.object(["id": .string("reply-1"), "title": .string("Reply"), "allowsReply": .bool(true)])])]
}
let notification = PhoneNotification(payload: notificationPayload())!
try expect(notification.actions.first?.allowsReply == true && notification.text == "Hello 🔔", "Notification actions and Unicode decode")
try expect(PhoneNotification(payload: [:]) == nil, "Notification requires stable key and revision")
var oversizedNotification = notificationPayload()
oversizedNotification["text"] = .string(String(repeating: "🔔", count: 1025))
try expect(PhoneNotification(payload: oversizedNotification) == nil, "Notification limits count UTF-8 bytes")
var malformedNotification = notificationPayload()
malformedNotification["actions"] = .string("not an action list")
try expect(PhoneNotification(payload: malformedNotification) == nil, "Malformed action container rejected")
malformedNotification = notificationPayload()
malformedNotification["title"] = .number(42)
try expect(PhoneNotification(payload: malformedNotification) == nil, "Wrong notification field types rejected")
var duplicateActions = notificationPayload()
duplicateActions["actions"] = .array(Array(repeating: .object(["id": .string("duplicate"), "title": .string("Action")]), count: 2))
try expect(PhoneNotification(payload: duplicateActions) == nil, "Duplicate action IDs rejected")
var tooManyActions = notificationPayload()
tooManyActions["actions"] = .array((0..<5).map { .object(["id": .string("action-\($0)"), "title": .string("Action")]) })
try expect(PhoneNotification(payload: tooManyActions) == nil, "Too many notification actions rejected")
var notificationStore = PhoneNotificationStore()
try expect(notificationStore.accept(notification), "Fresh notification triggers alert")
try expect(!notificationStore.accept(notification), "Duplicate notification does not re-alert")
let updatedNotification = PhoneNotification(payload: notificationPayload(revision: "v2"))!
try expect(notificationStore.accept(updatedNotification) && notificationStore.entries.count == 1, "Update replaces same notification key")
try expect(!notificationStore.remove(key: "test-key", revision: "v1") && notificationStore.entries.count == 1, "Stale removal cannot delete newer revision")
try expect(notificationStore.remove(key: "test-key", revision: "v2"), "Phone removal clears matching notification")
try expect(!notificationStore.accept(PhoneNotification(payload: notificationPayload(snapshot: true))!), "Reconnect snapshot does not trigger alerts")
for index in 0..<40 {
    _ = notificationStore.accept(PhoneNotification(payload: notificationPayload(key: "key-\(index)"))!)
}
try expect(notificationStore.entries.count == 30 && notificationStore.entries.first?.key == "key-39", "Notification state is bounded and newest first")
try expect(!notificationStore.contains(key: "key-0", revision: "v1"), "Evicted notifications cannot receive actions")
notificationStore.reset()
try expect(notificationStore.entries.isEmpty, "Disconnect clears notification content")
for kind in ["notif.postedV2", "notif.removed", "notif.reset", "notif.action", "notif.dismiss", "notif.subscribe"] {
    try expect(!PhoneHandshakePolicy.acceptsPlaintext(type: kind, isSecure: false), "Notification protocol refuses plaintext \(kind)")
}
var fixtureNotificationPayload = notificationPayload(key: "0|dev.sapphire.companion|2001|sapphire-notification-fixture|fixture")
fixtureNotificationPayload["appId"] = .string("dev.sapphire.companion")
fixtureNotificationPayload["title"] = .string("Sapphire mirroring test")
try expect(PhoneNotification(payload: fixtureNotificationPayload)!.isDiagnosticFixture, "Diagnostic commands recognize only the fixed companion fixture")
fixtureNotificationPayload["appId"] = .string("other.app")
try expect(!PhoneNotification(payload: fixtureNotificationPayload)!.isDiagnosticFixture, "Diagnostic commands cannot target other apps")
fixtureNotificationPayload["appId"] = .string("dev.sapphire.companion")
fixtureNotificationPayload["title"] = .string("Real notification")
try expect(!PhoneNotification(payload: fixtureNotificationPayload)!.isDiagnosticFixture, "Diagnostic commands cannot target ordinary companion notifications")
var dismissalStore = PhoneNotificationStore()
_ = dismissalStore.accept(notification)
dismissalStore.dismiss(notification)
try expect(!dismissalStore.contains(key: notification.key, revision: notification.revision), "Dismiss removes the Mac entry immediately")
try expect(!dismissalStore.accept(notification) && dismissalStore.entries.isEmpty, "Delayed duplicate cannot resurrect a dismissed notification")
try expect(!dismissalStore.remove(key: notification.key, revision: notification.revision), "Phone acknowledgement after local dismissal is idempotent")
try expect(dismissalStore.accept(updatedNotification), "A genuinely new revision can appear after dismissal")
dismissalStore.dismiss(notification)
try expect(dismissalStore.contains(key: updatedNotification.key, revision: updatedNotification.revision), "Stale dismissal cannot remove a newer revision")
dismissalStore.reset()
try expect(dismissalStore.accept(notification), "A fresh connection resets local dismissal bookkeeping")
print("Passed \(checks) phone protocol checks, including independent Java crypto fixtures.")

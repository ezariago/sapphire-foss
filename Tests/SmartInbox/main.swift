import AppKit
@main struct Checks {
    @MainActor static func main() {
        for (text, code) in [("Your verification code is 123456", "123456"), ("Use code: 4321", "4321"), ("Kode verifikasi: 654321", "654321"), ("Your OTP is A1b2C3", "A1b2C3")] {
            assert(VerificationCodeDetector.find(in: text) == code, text)
        }
        for text in ["Order 123456 arrived", "Your verification code for 2026 is 123456", "Invoice $1234", "Verification date 2026-10-24", "Code is 1234 5678", "Your code is ١٢٣٤٥٦", String(repeating: "x", count: 8193)] {
            assert(VerificationCodeDetector.find(in: text) == nil, text)
        }
        let ups = "1Z0000000000000000"
        assert(SmartInboxPolicy.parcelReferences(in: "UPS tracking \(ups)").count == 1)
        assert(SmartInboxPolicy.parcelReferences(in: ups).isEmpty)
        assert(SmartInboxPolicy.parcelReferences(in: "FedEx 123456789012").first?.0 == .fedex)
        assert(SmartInboxPolicy.parcelReferences(in: "DHL 1234567890").first?.0 == .dhl)
        assert(SmartInboxPolicy.parcelReferences(in: "USPS 12345678901234567890").first?.0 == .usps)
        assert(ParcelCarrier.ups.trackingURL(ups)?.host == "www.ups.com")
        assert(ParcelCarrier.ups.trackingURL("../unsafe") == nil && ParcelCarrier.amazon.trackingURL("TBA123") == nil)
        let clock = TestClock(), lane = PasteboardLane.shared
        defer { lane.board.releaseGlobally() }
        let monitor = SmartInboxMonitor(clock: { clock.read() }, automaticMaintenance: false, sessionLocked: { false }, pasteboardCount: { lane.board.changeCount })
        let date = Date(timeIntervalSince1970: 10000)
        func ingest(_ id: String, _ body: String, age: Double = 0, ticket: UInt64? = nil) {
            monitor.ingestNotification(id: id, source: "Fixture", title: "", body: body, date: date.addingTimeInterval(-age), now: date, ticket: ticket)
        }
        ingest("before", "Your OTP is 123456"); assert(monitor.latestOTP == nil)
        monitor.start(); monitor.start()
        ingest("one", "Your OTP is 123456")
        let first = monitor.latestOTP!
        assert(first.body.isEmpty && first.id != first.code)
        ingest("one", "Your OTP is 999999"); assert(monitor.latestOTP == first)
        assert(monitor.otpForPresentation(keepingCurrent: false)?.id == first.id)
        assert(monitor.otpForPresentation(keepingCurrent: false) == nil)
        assert(monitor.otpForPresentation(keepingCurrent: true)?.id == first.id)
        var copied = false
        monitor.copyOTP(first) { copied = $0 }; lane.flush()
        assert(copied && lane.board.string(forType: .string) == first.code)
        assert(lane.board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        monitor.copyOTP(first) { copied = $0 }
        lane.board.clearContents(); lane.board.setString("Newer copy", forType: .string); lane.flush()
        assert(!copied && lane.board.string(forType: .string) == "Newer copy")
        ingest("same-code-new-id", "Your OTP is 123456")
        assert(monitor.otpForPresentation(keepingCurrent: false) == nil)
        let ticket = SmartInboxInputGate.shared.capture()!
        monitor.copyOTP(monitor.latestOTP!) { copied = $0 }
        SettingsModel.shared.settings.smartInboxEnabled = false; SettingsModel.shared.settings.smartInboxEnabled = true
        lane.flush(); assert(!copied && monitor.latestOTP == nil)
        ingest("stale", "Your OTP is 123456", ticket: ticket); assert(monitor.latestOTP == nil)
        ingest("phone:two", "Your OTP is 123456"); assert(monitor.latestOTP != nil)
        monitor.removePhoneItems(); assert(monitor.latestOTP == nil)
        ingest("old", "Your OTP is 123456", age: 301); assert(monitor.latestOTP == nil)
        ingest("parcel", "UPS tracking \(ups)")
        let parcel = monitor.activeParcels.first!
        assert(parcel.status == "Unverified" && parcel.sourceEmailSubject == nil)
        assert(monitor.parcelForPresentation()?.id == parcel.id && monitor.parcelForPresentation() == nil)
        assert(monitor.parcelForPresentation(currentID: parcel.id)?.id == parcel.id)
        monitor.copyParcel(parcel) { copied = $0 }; monitor.removeParcel(parcel.id); lane.flush(); assert(!copied)
        ingest("fresh", "Your OTP is 654321")
        clock.set(401); monitor.expire(); assert(monitor.latestOTP == nil)
        clock.set(500); ingest("rollback", "Your OTP is 654321"); clock.set(499); monitor.expire(); assert(monitor.latestOTP == nil)
        clock.set(1000)
        for i in 0..<40 { ingest("parcel-\(i)", "UPS tracking 1Z" + String(format: "%016d", i)) }
        assert(monitor.activeParcels.count == 30)
        clock.set(1000); ingest("end", "Your OTP is 654321"); monitor.stop(); assert(monitor.latestOTP == nil && monitor.activeParcels.isEmpty)
        monitor.start(); assert(monitor.latestOTP == nil); monitor.stop()
        let lockState = TestClock(); lockState.set(0)
        let lockedMonitor = SmartInboxMonitor(clock: { clock.read() }, automaticMaintenance: false,
            sessionLocked: { lockState.read() != 0 }, pasteboardCount: { lane.board.changeCount })
        lockedMonitor.start()
        lockedMonitor.ingestNotification(id: "lock-copy", source: "Fixture", title: "", body: "OTP: 123456", date: date, now: date)
        let beforeLock = lockedMonitor.latestOTP!
        lockedMonitor.copyOTP(beforeLock) { copied = $0 }
        lockState.set(1); lane.flush(); assert(!copied)
        lockedMonitor.expire(); assert(lockedMonitor.latestOTP == nil)
        lockedMonitor.ingestNotification(id: "while-locked", source: "Fixture", title: "", body: "OTP: 123456", date: date, now: date)
        assert(lockedMonitor.latestOTP == nil)
        lockedMonitor.stop()
        print("Passed conservative code/reference parsing, bounded production inbox lifecycle, replay/expiry/rollback, private named-pasteboard writes and stale copy/configuration/input rejection fixtures. No user notifications, Mail, general clipboard or network used.")
    }
}

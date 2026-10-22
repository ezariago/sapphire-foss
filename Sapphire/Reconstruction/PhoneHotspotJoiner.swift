#if !SAPPHIRE_FULL_BUILD
import CoreWLAN
import Foundation

// CoreWLAN scan/association are blocking. Keep both off the main actor and never
// persist or log the passphrase received over the authenticated Bluetooth link.
actor PhoneHotspotJoiner {
    private var joinedSSID: String?

    func join(_ credentials: PhoneHotspotCredentials) throws {
        guard let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() else {
            throw JoinError.wifiOff
        }
        for _ in 0..<5 {
            try Task.checkCancellation()
            let networks = try wifi.scanForNetworks(withSSID: Data(credentials.ssid.utf8))
            if let network = networks.first(where: { $0.ssid == credentials.ssid && $0.supportsSecurity(.wpa2Personal) }) {
                try Task.checkCancellation()
                try wifi.associate(to: network, password: credentials.passphrase)
                if Task.isCancelled {
                    if wifi.ssid() == credentials.ssid { wifi.disassociate() }
                    throw CancellationError()
                }
                joinedSSID = credentials.ssid
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }
        throw JoinError.notFound
    }

    func leave() {
        if let joinedSSID, let wifi = CWWiFiClient.shared().interface(), wifi.ssid() == joinedSSID {
            wifi.disassociate()
        }
        joinedSSID = nil
    }

    enum JoinError: LocalizedError {
        case wifiOff, notFound
        var errorDescription: String? {
            switch self {
            case .wifiOff: "Turn on Wi-Fi on your Mac and try again."
            case .notFound: "The phone’s network was not found. Keep the phone nearby and allow Sapphire Location access in System Settings → Privacy & Security → Location Services."
            }
        }
    }
}
#endif

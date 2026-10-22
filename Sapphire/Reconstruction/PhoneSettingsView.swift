#if !SAPPHIRE_FULL_BUILD
import SwiftUI
import CoreImage.CIFilterBuiltins

struct ContinuitySettingsView: View {
    @ObservedObject private var link = ReconstructedPhoneLink.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Phone / Android").font(.largeTitle.bold())
                Text("Local reconstruction · Bluetooth connection")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(link.status).textSelection(.enabled)
                if let error = link.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                HStack {
                    Button("Pair a phone", action: link.beginPairing)
                    if link.pairedName != nil {
                        Button("Reconnect", action: link.start).disabled(link.isConnecting || link.isSecure)
                    }
                    Button("Disconnect", action: link.disconnect)
                }
                if let name = link.pairedName { Label(name, systemImage: "iphone") }
                nearbyPhones
                if let payload = link.qrPayload {
                    VStack(alignment: .leading, spacing: 10) {
                        if let image = qrImage(payload) {
                            Image(nsImage: image).interpolation(.none).resizable()
                                .scaledToFit().frame(width: 320, height: 320)
                                .padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("Sapphire phone pairing QR code")
                        }
                        Text("Open Pair your Mac in the Android app. The Mac connects automatically when one phone is ready to pair; otherwise click Connect above. Then choose Pair with a code on the phone and scan this code. Keep both devices unlocked.")
                        Text("The code expires after three minutes. Accept Bluetooth permission and system pairing prompts if shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let sas = link.sas {
                    Text(sas).font(.system(size: 42, weight: .bold, design: .monospaced))
                    Text("Confirm only if the same six digits appear on your phone.")
                    Button("Codes match — confirm on Mac", action: link.confirmPairing)
                        .disabled(!link.awaitingConfirmation)
                }
                if link.isSecure {
                    GroupBox("Phone controls") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let battery = link.batteryPercent { Label("Battery: \(battery)%", systemImage: "battery.100") }
                            if !link.mediaTitle.isEmpty { Text(link.mediaTitle).font(.headline) }
                            HStack {
                                Button("Previous") { link.sendMedia("previous") }
                                Button("Play / pause") { link.sendMedia("toggle") }
                                Button("Next") { link.sendMedia("next") }
                            }
                            Toggle("Automatically send Mac clipboard text to phone", isOn: $link.automaticClipboard)
                            Text("Sends new text copies while connected. Password-manager and private clipboard items stay on this Mac. Text must be under 12 KB.")
                                .font(.caption).foregroundStyle(.secondary)
                            Divider()
                            Text("Instant hotspot").font(.headline)
                            Text(link.hotspotInternet ? "Connect using your phone’s mobile hotspot. Requires Sapphire Hotspot Helper and authorized Shizuku access on Android. This switches your Mac’s Wi-Fi connection." : "Connect to your phone’s local Wi-Fi network. This Android companion does not provide mobile internet sharing. This switches your Mac’s Wi-Fi connection.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !link.hotspotStatus.isEmpty { Text(link.hotspotStatus).textSelection(.enabled) }
                            HStack {
                                Button(link.isHotspotBusy ? "Connecting…" : "Connect to phone hotspot", action: link.requestHotspot)
                                    .disabled(link.isHotspotBusy || link.hotspotConnected)
                                if link.hotspotConnected {
                                    Button("Disconnect hotspot", action: link.leaveHotspot)
                                }
                            }
                            if let text = link.receivedText {
                                Text("Text received from phone").font(.headline)
                                Text(text).lineLimit(5).textSelection(.enabled)
                                Button("Copy received text on Mac", action: link.copyReceivedText)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                PhoneNotificationsSettingsView()
                Text("This replacement currently supports encrypted Bluetooth pairing, phone status, text clipboard messages, hotspot control and notification mirroring with supported actions/replies. Wi-Fi transfer, phone storage, screen mirroring, calls, widgets and camera/microphone support are not implemented yet.")
                    .font(.caption).foregroundStyle(.secondary)
                if !link.isSecure && link.hotspotConnected {
                    Button("Disconnect phone hotspot", action: link.leaveHotspot)
                }
                if link.pairedName != nil { Button("Forget this phone", role: .destructive, action: link.forget) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var nearbyPhones: some View {
        if link.isScanning || !link.nearby.isEmpty {
            GroupBox("Nearby Sapphire phones") {
                VStack(alignment: .leading, spacing: 12) {
                    if link.nearby.isEmpty { Text("Looking for your phone…") }
                    ForEach(link.nearby) { phone in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(phone.name)
                                Text("Signal: \(phone.rssi) dBm" + (phone.advertisement?.isPairing == true ? " · Ready to pair" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Connect") { link.connect(phone.id) }
                                .disabled(link.isConnecting || link.isSecure)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
    }

    private func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// Shared by the compact notch status and the expanded device panel.
struct PhoneSignalBars: View {
    let level: Int?
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(level.map { bar < $0 } == true ? Color.white : Color.white.opacity(0.22))
                    .frame(width: 3, height: CGFloat(3 + bar * 3))
            }
        }
        .frame(width: 17, height: 12)
        .overlay { if level == nil { Text("?").font(.system(size: 9, weight: .bold)) } }
        .accessibilityLabel(level.map { "Mobile signal: \($0) of 4 bars" } ?? "Mobile signal unavailable")
    }
}

struct PhoneNotchStatusView: View {
    @ObservedObject private var link = ReconstructedPhoneLink.shared
    private var snapshot: ContinuityConnectivitySnapshot { ContinuityManager.shared.connectivity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "iphone").font(.system(size: 28)).foregroundStyle(link.isSecure ? Color.green : Color.gray)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.pairedName ?? "Your phone").font(.headline)
                        Text(link.isSecure ? "Connected · Encrypted Bluetooth" : "Disconnected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let battery = snapshot.phoneBatteryPercent {
                        Label("\(battery)%", systemImage: snapshot.phoneCharging ? "battery.100percent.bolt" : "battery.100percent")
                            .font(.callout.monospacedDigit())
                    }
                }
                HStack {
                    PhoneSignalBars(level: snapshot.phoneSignalLevel)
                    Text(snapshot.phoneCarrier ?? "Carrier unavailable").lineLimit(1)
                    Spacer()
                    Text(snapshot.phoneSignalLevel.map { "\($0)/4 bars" } ?? "Signal unavailable")
                        .foregroundStyle(.secondary)
                }.font(.callout)
                if let network = snapshot.phoneNetwork {
                    Label(network == .wifi ? "Phone using Wi-Fi" : network == .cellular ? "Phone using mobile data" : "Phone has no active network",
                          systemImage: network == .wifi ? "wifi" : network == .cellular ? "antenna.radiowaves.left.and.right" : "network.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Label("Instant hotspot", systemImage: "personalhotspot").font(.headline)
                    Spacer()
                    if link.isHotspotBusy { ProgressView().controlSize(.small) }
                    if link.hotspotConnected {
                        Button("Disconnect", action: link.leaveHotspot).disabled(link.isHotspotBusy)
                    } else {
                        Button(link.isHotspotBusy ? "Connecting…" : "Connect", action: link.requestHotspot)
                            .disabled(!link.isSecure || link.isHotspotBusy)
                    }
                }
                Text(link.hotspotStatus.isEmpty ? "Use your phone’s mobile internet on this Mac." : link.hotspotStatus)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !link.isSecure {
                    HStack {
                        Text(link.status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if link.pairedName != nil {
                            Button("Reconnect", action: link.start).disabled(link.isConnecting)
                        }
                    }
                }
            }.padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }
}
#endif

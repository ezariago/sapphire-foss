#if !SAPPHIRE_FULL_BUILD
import SwiftUI
struct SmartInboxStatusView: View {
    @ObservedObject private var monitor = SmartInboxMonitor.shared
    @State private var reveal = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected notification items").font(.headline)
            Text("Uses already permitted Mac and live phone notifications. The Mac's code-only notification filter also filters parcel inputs. Mail scanning, carrier status fetching and Amazon lookup are not implemented. Copied items are marked private; other clipboard apps may ignore that marker.").font(.caption).foregroundStyle(.secondary)
            if let event = monitor.latestOTP {
                HStack {
                    Text(event.source)
                    Text(reveal ? event.code : "••••••").monospaced()
                    Button(reveal ? "Hide" : "Reveal") { reveal.toggle() }
                    Button("Copy code") { monitor.copyOTP(event) { status = $0 ? "Copied privately." : "Code expired or clipboard changed." } }
                    Button("Dismiss") { monitor.dismissOTP() }
                }
            }
            ForEach(monitor.activeParcels.prefix(10)) { parcel in
                HStack {
                    Text(parcel.carrier.displayName + " · " + parcel.trackingNumber).font(.caption).monospaced()
                    Text("Unverified").font(.caption).foregroundStyle(.secondary)
                    Button("Copy reference") { monitor.copyParcel(parcel) { status = $0 ? "Copied privately." : "Reference expired or clipboard changed." } }
                    if let url = parcel.trackingURL { Link("Carrier site", destination: url) }
                    Button("Remove") { monitor.removeParcel(parcel.id) }
                }
            }
            if monitor.activeParcels.count > 10 { Text("Showing 10 of \(monitor.activeParcels.count) references.").font(.caption) }
            if monitor.latestOTP == nil && monitor.activeParcels.isEmpty { Text("No recent items detected.").foregroundStyle(.secondary) }
            if !status.isEmpty { Text(status).font(.caption) }
            Button("Clear detected items") { monitor.clear(); reveal = false }
        }.padding()
        .onChange(of: monitor.latestOTP?.id) { _, _ in reveal = false; status = "" }
    }
}
#endif

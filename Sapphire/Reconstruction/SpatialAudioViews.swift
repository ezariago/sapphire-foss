#if !SAPPHIRE_FULL_BUILD
import SwiftUI

private struct SpatialParameterSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var scale: Double = 100
    var suffix = "%"
    var format = "%.0f"
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value * scale) + suffix).monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            Slider(value: $value, in: range).accessibilityLabel(title)
        }
    }
}

private struct SpatialTapStatus: View {
    let bundleID: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(MultiAudioManager.shared.hasActiveTap(for: bundleID) ? "Mixer tap active" : "No active mixer tap for this app")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct EightDAudioView: View {
    let bundleID: String
    let appName: String
    @ObservedObject private var manager = MultiAudioManager.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text("8D · \(appName)").font(.headline)
                Toggle("Enable rotating stereo effect", isOn: setting(\.enabled))
                Text("Live controls for this app's stereo spatial effect. Per-app audio routing and macOS system-audio capture permission are required.").font(.caption).foregroundStyle(.secondary)
                SpatialTapStatus(bundleID: bundleID)
                SpatialParameterSlider(title: "Rotation speed", value: setting(\.rotationSpeed), range: 0.01...1, scale: 1, suffix: " turns/s", format: "%.2f")
                SpatialParameterSlider(title: "Depth", value: setting(\.depth))
                SpatialParameterSlider(title: "Distance effect", value: setting(\.distance))
                SpatialParameterSlider(title: "Elevation motion", value: setting(\.elevationMotion))
                SpatialParameterSlider(title: "Front/back motion", value: setting(\.frontBackMotion))
                SpatialParameterSlider(title: "Room size", value: setting(\.roomSize))
                SpatialParameterSlider(title: "Room spread", value: setting(\.roomSpread))
                SpatialParameterSlider(title: "Bass boost", value: setting(\.bassBoost), range: 0...12, scale: 1, suffix: " dB", format: "%.1f")
                SpatialParameterSlider(title: "Intensity", value: setting(\.intensity))
                SpatialParameterSlider(title: "Center focus", value: setting(\.centerFocus))
                Button("Reset 8D for this app") { manager.resetEightDAudio(for: bundleID) }
            }.padding(16)
        }.frame(width: 360, height: 460)
    }
    private func setting<Value>(_ key: WritableKeyPath<EightDAudioSettings, Value>) -> Binding<Value> {
        Binding(get: { manager.eightDAudioSettings(for: bundleID)[keyPath: key] }, set: { value in
            var settings = manager.eightDAudioSettings(for: bundleID)
            settings[keyPath: key] = value
            manager.setEightDAudioSettings(settings, for: bundleID)
        })
    }
}

struct SurroundAudioView: View {
    let bundleID: String
    let appName: String
    @ObservedObject private var manager = MultiAudioManager.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text("Surround · \(appName)").font(.headline)
                Toggle("Enable stereo widening and ambience", isOn: setting(\.enabled))
                Text("Live stereo processing for this app. Per-app audio routing and macOS system-audio capture permission are required.").font(.caption).foregroundStyle(.secondary)
                SpatialTapStatus(bundleID: bundleID)
                SpatialParameterSlider(title: "Stereo width", value: setting(\.width), range: 1...2.5, scale: 1, suffix: "×", format: "%.2f")
                SpatialParameterSlider(title: "Crossfeed", value: setting(\.crossfeed), range: 0...0.5)
                SpatialParameterSlider(title: "Ambience", value: setting(\.ambience))
                SpatialParameterSlider(title: "Depth", value: setting(\.depth))
                SpatialParameterSlider(title: "Center focus", value: setting(\.centerFocus))
                Button("Reset surround for this app") { manager.resetSurroundAudio(for: bundleID) }
            }.padding(16)
        }.frame(width: 360, height: 420)
    }
    private func setting<Value>(_ key: WritableKeyPath<SurroundAudioSettings, Value>) -> Binding<Value> {
        Binding(get: { manager.surroundAudioSettings(for: bundleID)[keyPath: key] }, set: { value in
            var settings = manager.surroundAudioSettings(for: bundleID)
            settings[keyPath: key] = value
            manager.setSurroundAudioSettings(settings, for: bundleID)
        })
    }
}
#endif

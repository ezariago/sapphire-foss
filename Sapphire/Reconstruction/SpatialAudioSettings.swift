// Spatial settings extracted from MultiAudioManager.swift.
// Original source by Shariq Charolia; retained under the repository LICENSE.
import Foundation

struct EightDAudioSettings: Equatable, Codable {
    var enabled: Bool = false
    var rotationSpeed: Double = 0.10
    var depth: Double = 0.88
    var distance: Double = 0.18
    var elevationMotion: Double = 0.85
    var frontBackMotion: Double = 0.92
    var roomSize: Double = 0.78
    var roomSpread: Double = 0.85
    var bassBoost: Double = 0.0
    var intensity: Double = 0.9
    var centerFocus: Double = 0.35

    private enum CodingKeys: String, CodingKey {
        case enabled, rotationSpeed, depth, distance, elevationMotion, frontBackMotion, roomSize, roomSpread, bassBoost, intensity, centerFocus
    }

    init(enabled: Bool = false, rotationSpeed: Double = 0.10, depth: Double = 0.88, distance: Double = 0.18, elevationMotion: Double = 0.85, frontBackMotion: Double = 0.92, roomSize: Double = 0.78, roomSpread: Double = 0.85, bassBoost: Double = 0.0, intensity: Double = 0.9, centerFocus: Double = 0.35) {
        self.enabled = enabled
        self.rotationSpeed = rotationSpeed
        self.depth = depth
        self.distance = distance
        self.elevationMotion = elevationMotion
        self.frontBackMotion = frontBackMotion
        self.roomSize = roomSize
        self.roomSpread = roomSpread
        self.bassBoost = bassBoost
        self.intensity = intensity
        self.centerFocus = centerFocus
        self = normalized()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        rotationSpeed = try values.decodeIfPresent(Double.self, forKey: .rotationSpeed) ?? 0.10
        depth = try values.decodeIfPresent(Double.self, forKey: .depth) ?? 0.88
        distance = try values.decodeIfPresent(Double.self, forKey: .distance) ?? 0.18
        elevationMotion = try values.decodeIfPresent(Double.self, forKey: .elevationMotion) ?? 0.85
        frontBackMotion = try values.decodeIfPresent(Double.self, forKey: .frontBackMotion) ?? 0.92
        roomSize = try values.decodeIfPresent(Double.self, forKey: .roomSize) ?? 0.78
        roomSpread = try values.decodeIfPresent(Double.self, forKey: .roomSpread) ?? 0.85
        bassBoost = try values.decodeIfPresent(Double.self, forKey: .bassBoost) ?? 0.0
        intensity = try values.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.9
        centerFocus = try values.decodeIfPresent(Double.self, forKey: .centerFocus) ?? 0.35
        self = normalized()
    }
    func normalized() -> Self {
        var value = self
        value.rotationSpeed = spatialValue(rotationSpeed, 0.01...1, fallback: 0.10)
        value.depth = spatialValue(depth, 0...1, fallback: 0.88)
        value.distance = spatialValue(distance, 0...1, fallback: 0.18)
        value.elevationMotion = spatialValue(elevationMotion, 0...1, fallback: 0.85)
        value.frontBackMotion = spatialValue(frontBackMotion, 0...1, fallback: 0.92)
        value.roomSize = spatialValue(roomSize, 0...1, fallback: 0.78)
        value.roomSpread = spatialValue(roomSpread, 0...1, fallback: 0.85)
        value.bassBoost = spatialValue(bassBoost, 0...12, fallback: 0)
        value.intensity = spatialValue(intensity, 0...1, fallback: 0.9)
        value.centerFocus = spatialValue(centerFocus, 0...1, fallback: 0.35)
        return value
    }
}

struct SurroundAudioSettings: Equatable, Codable {
    var enabled: Bool = false
    var width: Double = 1.7
    var crossfeed: Double = 0.12
    var ambience: Double = 0.4
    var depth: Double = 0.55
    var centerFocus: Double = 0.45

    private enum CodingKeys: String, CodingKey {
        case enabled, width, crossfeed, ambience, depth, centerFocus
    }

    init(enabled: Bool = false, width: Double = 1.7, crossfeed: Double = 0.12, ambience: Double = 0.4, depth: Double = 0.55, centerFocus: Double = 0.45) {
        self.enabled = enabled
        self.width = width
        self.crossfeed = crossfeed
        self.ambience = ambience
        self.depth = depth
        self.centerFocus = centerFocus
        self = normalized()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? 1.7
        crossfeed = try values.decodeIfPresent(Double.self, forKey: .crossfeed) ?? 0.12
        ambience = try values.decodeIfPresent(Double.self, forKey: .ambience) ?? 0.4
        depth = try values.decodeIfPresent(Double.self, forKey: .depth) ?? 0.55
        centerFocus = try values.decodeIfPresent(Double.self, forKey: .centerFocus) ?? 0.45
        self = normalized()
    }
    func normalized() -> Self {
        var value = self
        value.width = spatialValue(width, 1...2.5, fallback: 1.7)
        value.crossfeed = spatialValue(crossfeed, 0...0.5, fallback: 0.12)
        value.ambience = spatialValue(ambience, 0...1, fallback: 0.4)
        value.depth = spatialValue(depth, 0...1, fallback: 0.55)
        value.centerFocus = spatialValue(centerFocus, 0...1, fallback: 0.45)
        return value
    }
}

private func spatialValue(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
}


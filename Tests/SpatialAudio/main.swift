import Foundation

let defaults = EightDAudioSettings()
assert(!defaults.enabled && defaults.rotationSpeed == 0.10 && defaults.depth == 0.88)
let decodedDefaults = try JSONDecoder().decode(EightDAudioSettings.self, from: Data("{}".utf8))
assert(decodedDefaults == defaults)
var eightD = defaults
eightD.rotationSpeed = .infinity; eightD.depth = .nan; eightD.distance = -1
eightD.elevationMotion = 50; eightD.frontBackMotion = -50; eightD.roomSize = 1e300
eightD.roomSpread = -.infinity; eightD.bassBoost = .infinity; eightD.intensity = 100; eightD.centerFocus = -1
let safe = eightD.normalized()
assert(safe.rotationSpeed == 0.10 && safe.depth == 0.88 && safe.distance == 0)
assert(safe.elevationMotion == 1 && safe.frontBackMotion == 0 && safe.roomSize == 1)
assert(safe.roomSpread == 0.85 && safe.bassBoost == 0 && safe.intensity == 1 && safe.centerFocus == 0)
assert(safe.normalized() == safe)
let valid = EightDAudioSettings(enabled: true, rotationSpeed: 0.4, depth: 0.5, distance: 0.6, elevationMotion: 0.7,
    frontBackMotion: 0.8, roomSize: 0.9, roomSpread: 0.2, bassBoost: 3, intensity: 0.4, centerFocus: 0.5)
let data = try JSONEncoder().encode(valid)
let decodedValid = try JSONDecoder().decode(EightDAudioSettings.self, from: data)
assert(decodedValid == valid)
let old = try JSONDecoder().decode(EightDAudioSettings.self, from: Data(#"{"enabled":true,"depth":0.2}"#.utf8))
assert(old == EightDAudioSettings(enabled: true, depth: 0.2))
let malformed = try JSONDecoder().decode(EightDAudioSettings.self, from: Data(#"{"rotationSpeed":1e300,"bassBoost":-100}"#.utf8))
assert(malformed.rotationSpeed == 1 && malformed.bassBoost == 0)
var surround = SurroundAudioSettings()
surround.width = .nan; surround.crossfeed = .infinity; surround.ambience = -1; surround.depth = 2; surround.centerFocus = -.infinity
let safeSurround = surround.normalized()
assert(safeSurround.width == 1.7 && safeSurround.crossfeed == 0.12 && safeSurround.ambience == 0 && safeSurround.depth == 1 && safeSurround.centerFocus == 0.45)
assert(safeSurround.normalized() == safeSurround)
let surroundData = try JSONEncoder().encode(safeSurround)
let decodedSurround = try JSONDecoder().decode(SurroundAudioSettings.self, from: surroundData)
let decodedSurroundDefaults = try JSONDecoder().decode(SurroundAudioSettings.self, from: Data("{}".utf8))
assert(decodedSurround == safeSurround)
assert(decodedSurroundDefaults == SurroundAudioSettings())
print("Passed spatial-audio defaults, legacy decoding, all-parameter finite bounds, normalization idempotence and persistence fixtures; no mixer, capture tap or playback was started.")

import AVFoundation
import CoreVideo
import Foundation

@main struct GeneratedVideoFixture {
    @MainActor static func main() async {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("SapphireVideoFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("Generated.mov")
            let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000, AVVideoMaxKeyFrameIntervalKey: 1]
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720
            ])
            guard writer.canAdd(input) else { throw Failure.encoding }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? Failure.encoding }
            writer.startSession(atSourceTime: .zero)
            let deadline = ProcessInfo.processInfo.systemUptime + 45
            var seed: UInt32 = 0x53415050
            for frame in 0..<30 {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else { throw writer.error ?? Failure.encoding }
                    try await Task.sleep(for: .milliseconds(2))
                }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw Failure.encoding }
                CVPixelBufferLockBaseAddress(buffer, [])
                let address = CVPixelBufferGetBaseAddress(buffer)!
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                // Deterministic synthetic noise: no camera, screen or user file.
                for y in 0..<720 {
                    let row = address.advanced(by: y * stride).assumingMemoryBound(to: UInt32.self)
                    for x in 0..<1280 {
                        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                        row[x] = 0xFF000000 | (seed & 0x00FFFFFF)
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                    throw writer.error ?? Failure.encoding
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? Failure.encoding }
            let original = try Data(contentsOf: source)
            let result = try await NativeMediaProcessor.optimize(source)
            guard result.kind == .video, result.savedBytes > 0, result.outputURL != source,
                  result.outputURL.pathExtension == "mp4" else { throw Failure.export }
            let after = try Data(contentsOf: source)
            guard after == original else { throw Failure.sourceChanged }
            let asset = AVURLAsset(url: result.outputURL)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first, tracks.count == 1,
                  duration.isFinite, abs(duration - 1) < 0.15 else { throw Failure.export }
            let size = try await track.load(.naturalSize)
            guard size.width > 0, size.height > 0, size.width <= 1280, size.height <= 720 else { throw Failure.export }
            let generator = AVAssetImageGenerator(asset: asset)
            let frame = try await generator.image(at: .zero).image
            guard frame.width > 0, frame.height > 0 else { throw Failure.export }
            print("Passed generated H.264 video compression, MP4 track/duration/dimensions, frame decoding and source-byte preservation. No playback, capture, microphone or user file used.")
        } catch {
            fputs("Generated video fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }
    private enum Failure: Error { case encoding, export, sourceChanged }
}

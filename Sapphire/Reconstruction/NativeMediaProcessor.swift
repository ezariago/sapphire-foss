#if !SAPPHIRE_FULL_BUILD
import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum MediaOptimizeKind: String {
    case image, pdf, video, audio
    var actionTitle: String { "Optimize \(rawValue.capitalized)" }
    var systemImage: String {
        switch self { case .image: "photo"; case .pdf: "doc.richtext"; case .video: "film"; case .audio: "waveform" }
    }
}
struct MediaOptimizeResult: Equatable {
    let sourceURL: URL
    let outputURL: URL
    let kind: MediaOptimizeKind
    let originalBytes: Int64
    let optimizedBytes: Int64
    var savedBytes: Int64 { max(0, originalBytes - optimizedBytes) }
    var savedPercent: Int { originalBytes > 0 ? Int(Double(savedBytes) / Double(originalBytes) * 100) : 0 }
}
enum MediaOptimizeError: LocalizedError, Equatable {
    case premiumRequired, unsupportedFile, noSavings, operationFailed(String)
    var errorDescription: String? {
        switch self {
        case .premiumRequired: "Media tools are available in Sapphire FOSS."
        case .unsupportedFile: "This file type is not supported by the native media optimizer."
        case .noSavings: "The optimized copy was not smaller. The original is unchanged and no larger copy was retained."
        case .operationFailed(let message): message
        }
    }
}
enum MediaOptimizer {
    static func kind(for url: URL) -> MediaOptimizeKind? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "webp": .image
        case "pdf": .pdf
        case "mp4", "mov", "m4v": .video
        case "m4a", "mp3", "wav", "aif", "aiff", "flac": .audio
        default: nil
        }
    }
    static func canOCR(_ url: URL) -> Bool { let kind = kind(for: url); return kind == .image || kind == .pdf }
}

enum NativeMediaProcessor {
    static func optimize(_ source: URL, quality: Double = 0.75, maxDimension: Double = 2048) async throws -> MediaOptimizeResult {
        guard source.isFileURL, let kind = MediaOptimizer.kind(for: source) else { throw MediaOptimizeError.unsupportedFile }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true, let bytes = properties.fileSize, bytes > 0 else { throw MediaOptimizeError.unsupportedFile }
        let quality = quality.isFinite ? min(1, max(0.1, quality)) : 0.75
        let dimension = Int(maxDimension.isFinite ? min(8192, max(64, maxDimension)) : 2048)
        var output = source.deletingPathExtension().appendingPathExtension("optimized-\(UUID().uuidString.prefix(8)).\(source.pathExtension)")
        var finished = false
        defer { if !finished { try? FileManager.default.removeItem(at: output) } }
        switch kind {
        case .image:
            guard bytes <= 200 * 1024 * 1024, let input = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(input) == 1,
                  let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: dimension] as CFDictionary) else {
                throw MediaOptimizeError.operationFailed("The image is too large, animated, multipage or unreadable.")
            }
            let transparent = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
            let type: UTType = transparent ? .png : .jpeg
            output = source.deletingPathExtension().appendingPathExtension("optimized-\(UUID().uuidString.prefix(8)).\(transparent ? "png" : "jpg")")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { throw MediaOptimizeError.operationFailed("Cannot create the optimized image beside the source.") }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MediaOptimizeError.operationFailed("Image encoding failed.") }
        case .pdf:
            guard bytes <= 300 * 1024 * 1024, let document = PDFDocument(url: source), !document.isEncrypted else { throw MediaOptimizeError.operationFailed("The PDF is too large, encrypted or unreadable.") }
            guard document.write(to: output, withOptions: [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: true]) else { throw MediaOptimizeError.operationFailed("PDF optimization failed.") }
        case .video, .audio:
            let asset = AVURLAsset(url: source)
            let preset = kind == .audio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetMediumQuality
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw MediaOptimizeError.operationFailed("This media cannot be exported by macOS.") }
            let fileType: AVFileType = kind == .audio ? .m4a : .mp4
            guard session.supportedFileTypes.contains(fileType) else { throw MediaOptimizeError.operationFailed("The media cannot be exported in the selected format.") }
            output = source.deletingPathExtension().appendingPathExtension("optimized-\(UUID().uuidString.prefix(8)).\(kind == .audio ? "m4a" : "mp4")")
            session.shouldOptimizeForNetworkUse = true
            if #available(macOS 15.0, *) {
                try await session.export(to: output, as: fileType)
            } else {
                session.outputURL = output
                session.outputFileType = fileType
                let success = await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume(returning: session.status == .completed) }
                }
                guard success else { throw MediaOptimizeError.operationFailed(session.error?.localizedDescription ?? "Media export failed.") }
            }
        }
        try Task.checkCancellation()
        let optimized = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard optimized > 0, optimized < bytes else { throw MediaOptimizeError.noSavings }
        QuarantineAttribute.copy(from: [source], to: output, recursively: false)
        finished = true
        return MediaOptimizeResult(sourceURL: source, outputURL: output, kind: kind, originalBytes: Int64(bytes), optimizedBytes: Int64(optimized))
    }

    static func recognizeText(in source: URL, language: String = "en-US", useCPUOnly: Bool = false) throws -> String {
        guard source.isFileURL, MediaOptimizer.canOCR(source),
              let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              bytes > 0, bytes <= 300 * 1024 * 1024 else { throw MediaOptimizeError.unsupportedFile }
        if source.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: source), !document.isEncrypted, document.pageCount <= 100 else {
                throw MediaOptimizeError.operationFailed("OCR supports unencrypted PDFs of up to 100 pages.")
            }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pages.append(text); continue }
                guard let reference = page.pageRef else { continue }
                let bounds = reference.getBoxRect(.mediaBox)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { continue }
                let scale = min(3, 2400 / max(1, max(bounds.width, bounds.height)))
                let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.concatenate(reference.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(reference)
                if let image = context.makeImage() { pages.append(try recognize(image, language: language, useCPUOnly: useCPUOnly)) }
            }
            return String(pages.joined(separator: "\n\n").prefix(1_000_000))
        }
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary) else { throw MediaOptimizeError.unsupportedFile }
        return try recognize(image, language: language, useCPUOnly: useCPUOnly)
    }
    private static func recognize(_ image: CGImage, language: String, useCPUOnly: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = useCPUOnly
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if (try? request.supportedRecognitionLanguages().contains(language)) == true { request.recognitionLanguages = [language] }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).sorted {
            let rowA = Int(($0.boundingBox.midY * 50).rounded())
            let rowB = Int(($1.boundingBox.midY * 50).rounded())
            return rowA != rowB ? rowA > rowB : $0.boundingBox.minX < $1.boundingBox.minX
        }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
#endif

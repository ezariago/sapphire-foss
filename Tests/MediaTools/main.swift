import AppKit
import AVFoundation
import ImageIO
import PDFKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    var phase = "fixture setup"
    do {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SapphireMediaFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 350, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 350).fill()
        ("SAPPHIRE 2468" as NSString).draw(at: NSPoint(x: 40, y: 120), withAttributes: [.font: NSFont.systemFont(ofSize: 80), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let source = root.appendingPathComponent("Fixture.tiff")
        let original = bitmap.tiffRepresentation!
        try original.write(to: source)
        phase = "image compression"
        let result = try await NativeMediaProcessor.optimize(source, maxDimension: 500)
        assert(result.savedBytes > 0 && result.savedPercent > 0 && result.outputURL != source)
        let stillOriginal = try Data(contentsOf: source)
        assert(stillOriginal == original)
        let compressed = CGImageSourceCreateWithURL(result.outputURL as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(compressed, 0, nil)!
        assert(max(image.width, image.height) <= 500)
        phase = "image OCR"
        let text = try NativeMediaProcessor.recognizeText(in: source)
        assert(text.contains("SAPPHIRE") && text.contains("2468"), "OCR result: \(text)")
        let pdf = PDFDocument()
        let nsImage = NSImage(size: NSSize(width: 1000, height: 350)); nsImage.addRepresentation(bitmap)
        pdf.insert(PDFPage(image: nsImage)!, at: 0)
        let pdfURL = root.appendingPathComponent("Fixture.pdf")
        assert(pdf.write(to: pdfURL))
        phase = "PDF OCR"
        let pdfText = try NativeMediaProcessor.recognizeText(in: pdfURL)
        assert(pdfText.contains("SAPPHIRE") && pdfText.contains("2468"))
        phase = "PDF compression"
        do {
            let optimizedPDF = try await NativeMediaProcessor.optimize(pdfURL)
            assert(PDFDocument(url: optimizedPDF.outputURL)?.pageCount == 1)
        } catch MediaOptimizeError.noSavings { /* Already compressed is a valid outcome. */ }
        let wav = root.appendingPathComponent("Silent.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        buffer.frameLength = 44100
        for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: 44100) }
        do {
            let audio = try AVAudioFile(forWriting: wav, settings: format.settings)
            try audio.write(from: buffer)
        }
        phase = "audio compression"
        let audioResult = try await NativeMediaProcessor.optimize(wav)
        assert(audioResult.kind == .audio && audioResult.savedBytes > 0 && audioResult.outputURL.pathExtension == "m4a")
        print("Passed image compression/dimensions/source preservation, image/PDF OCR, PDF export and silent audio compression fixtures.")
        exit(0)
    } catch {
        let detail = error as NSError
        fputs("Media fixture failure during \(phase): \(error) [domain=\(detail.domain), code=\(detail.code)]\n", stderr)
        if let underlying = detail.userInfo[NSUnderlyingErrorKey] as? NSError {
            fputs("Underlying error domain=\(underlying.domain), code=\(underlying.code)\n", stderr)
        }
        exit(1)
    }
}
app.run()

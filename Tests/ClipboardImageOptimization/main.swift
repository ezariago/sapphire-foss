import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct Checks {
    static func imageData(type: UTType, count: Int = 1) -> Data {
        let context = CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, count, nil)!
        for _ in 0..<count { CGImageDestinationAddImage(destination, image, nil) }
        assert(CGImageDestinationFinalize(destination))
        return data as Data
    }
    static func put(_ board: NSPasteboard, data: Data, type: NSPasteboard.PasteboardType = .tiff, extras: [NSPasteboard.PasteboardType: Data] = [:]) {
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        for (type, value) in extras { item.setData(value, forType: type) }
        board.clearContents(); assert(board.writeObjects([item]))
    }
    static func main() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = imageData(type: .tiff)
        let encoder = ClipboardImageEncoder()
        guard let png = await encoder.optimize(original, maxDimension: 200) else { fatalError("Fixture should shrink") }
        assert(png.count < original.count)
        let decoded = CGImageSourceCreateWithData(png as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
        assert(image.width == 200 && image.height == 100)
        assert([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo))
        let animated = await encoder.optimize(imageData(type: .tiff, count: 2), maxDimension: 200)
        assert(animated == nil)
        let oversized = await encoder.optimize(Data(repeating: 0, count: ClipboardImageOptimizationTransaction.maxBytes + 1), maxDimension: 200)
        assert(oversized == nil)
        let invalid = await encoder.optimize(Data([1, 2, 3]), maxDimension: 200)
        assert(invalid == nil)
        // PNG input is accepted independently from TIFF's legacy alias.
        put(board, data: imageData(type: .png), type: .png)
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount) != nil)
        let state = ClipboardImageOptimizationState()
        let enabled = ClipboardImageOptimizationConfiguration(enabled: true, maxDimension: 200)
        assert(ClipboardImageOptimizationConfiguration(enabled: true, maxDimension: .nan).maxDimension == 2048)
        assert(ClipboardImageOptimizationConfiguration(enabled: true, maxDimension: Double.greatestFiniteMagnitude).maxDimension == 4096)
        assert(ClipboardImageOptimizationConfiguration(enabled: true, maxDimension: -1).maxDimension == 64)
        let ticket = state.configure(enabled)
        assert(state.configure(enabled) == ticket && state.accepts(ticket))
        put(board, data: original)
        let input = ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount)!
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount - 1) == nil)
        state.configure(.init(enabled: false, maxDimension: 200)); state.configure(enabled)
        assert(!ClipboardImageOptimizationTransaction.commit(png, input: input, to: board, isCurrent: { state.accepts(ticket) }))
        assert(board.data(forType: .tiff) == original)
        let freshTicket = state.ticket().1
        var checks = 0
        assert(!ClipboardImageOptimizationTransaction.commit(png, input: input, to: board, isCurrent: { checks += 1; return checks == 1 }))
        assert(board.data(forType: .tiff) == original)
        board.clearContents(); board.setString("Newer isolated copy", forType: .string)
        assert(!ClipboardImageOptimizationTransaction.commit(png, input: input, to: board, isCurrent: { true }))
        assert(board.string(forType: .string) == "Newer isolated copy")
        put(board, data: original, extras: [.string: Data("Rich content".utf8)])
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount) == nil)
        put(board, data: original, extras: [.init("org.nspasteboard.ConcealedType"): Data()])
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount) == nil)
        let item = NSPasteboardItem(); item.setData(original, forType: .tiff)
        let secondItem = NSPasteboardItem(); secondItem.setData(original, forType: .tiff)
        board.clearContents(); board.writeObjects([item, secondItem])
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount) == nil)
        put(board, data: original)
        let current = ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount)!
        assert(!ClipboardImageOptimizationTransaction.commit(original, input: current, to: board, isCurrent: { true }))
        assert(ClipboardImageOptimizationTransaction.commit(png, input: current, to: board, isCurrent: { state.accepts(freshTicket) }))
        assert(board.data(forType: .png) == png)
        assert(board.string(forType: ClipboardImageOptimizationTransaction.marker) == "1")
        assert(ClipboardImageOptimizationTransaction.capture(board, expectedCount: board.changeCount) == nil)
        state.invalidate(); assert(!state.accepts(freshTicket))
        print("Passed real ImageIO resize/alpha/savings and multipage/invalid rejection, isolated named-pasteboard capture/write, stale revision/configuration rejection, rich/concealed/multi-item bypass and recursion marker fixtures. General clipboard untouched.")
    }
}

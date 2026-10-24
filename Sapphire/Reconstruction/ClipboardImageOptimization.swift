#if !SAPPHIRE_FULL_BUILD
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ClipboardImageOptimizationConfiguration: Equatable, Sendable {
    var enabled: Bool
    var maxDimension: Int
    var excludedApps: Set<String>
    init(enabled: Bool, maxDimension: Double, excludedApps: Set<String> = []) {
        self.enabled = enabled
        self.excludedApps = excludedApps
        self.maxDimension = Int(maxDimension.isFinite ? min(4096, max(64, maxDimension)) : 2048)
    }
}

/// The write lane can inspect configuration without accessing main-actor settings.
final class ClipboardImageOptimizationState: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration = ClipboardImageOptimizationConfiguration(enabled: false, maxDimension: 2048)
    private var generation: UInt64 = 0
    @discardableResult func configure(_ value: ClipboardImageOptimizationConfiguration) -> UInt64 {
        lock.withLock {
            if value != configuration { configuration = value; generation &+= 1 }
            return generation
        }
    }
    func invalidate() { lock.withLock { generation &+= 1 } }
    func ticket() -> (ClipboardImageOptimizationConfiguration, UInt64) { lock.withLock { (configuration, generation) } }
    func accepts(_ ticket: UInt64) -> Bool { lock.withLock { configuration.enabled && generation == ticket } }
}

struct ClipboardImageOptimizationInput: Sendable {
    let changeCount: Int
    let representations: [String: Data]
    let selectedType: String
    var data: Data { representations[selectedType]! }
}

enum ClipboardImageOptimizationTransaction {
    static let marker = NSPasteboard.PasteboardType("dev.sapphire.clipboard.optimized-image")
    static let maxBytes = 32 * 1024 * 1024
    static func capture(_ pasteboard: NSPasteboard, expectedCount: Int) -> ClipboardImageOptimizationInput? {
        let legacyTIFF = NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")
        let legacyPNG = NSPasteboard.PasteboardType("Apple PNG pasteboard type")
        let allowed: Set<NSPasteboard.PasteboardType> = [.png, .tiff, legacyTIFF, legacyPNG]
        guard pasteboard.changeCount == expectedCount, let items = pasteboard.pasteboardItems, items.count == 1 else { return nil }
        let item = items[0]
        // Board-wide types include automatic TIFF conversions for PNG. Read only
        // declared representations so those conversions do not inflate memory.
        let types = Set(item.types)
        guard !types.isEmpty, types.isSubset(of: allowed),
              Set(pasteboard.types ?? []).isSubset(of: allowed) else { return nil }
        var representations: [String: Data] = [:]
        var size = 0
        for type in types {
            guard let data = item.data(forType: type), !data.isEmpty,
                  data.count <= maxBytes - size else { return nil }
            size += data.count
            representations[type.rawValue] = data
        }
        guard pasteboard.changeCount == expectedCount else { return nil }
        let selected = types.contains(.png) ? NSPasteboard.PasteboardType.png : (types.contains(legacyPNG) ? legacyPNG : (types.contains(.tiff) ? .tiff : legacyTIFF))
        return .init(changeCount: expectedCount, representations: representations, selectedType: selected.rawValue)
    }
    /// Change-count checks are best effort across clients; macOS has no pasteboard CAS.
    static func commit(_ png: Data, input: ClipboardImageOptimizationInput, to pasteboard: NSPasteboard,
                       isCurrent: () -> Bool) -> Bool {
        guard !png.isEmpty, png.count < input.data.count, png.count <= maxBytes,
              isCurrent(), pasteboard.changeCount == input.changeCount,
              let items = pasteboard.pasteboardItems, items.count == 1,
              Set(items[0].types.map(\.rawValue)) == Set(input.representations.keys),
              input.representations.allSatisfy({ items[0].data(forType: .init($0.key)) == $0.value }) else { return false }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png), item.setString("1", forType: marker),
              isCurrent(), pasteboard.changeCount == input.changeCount else { return false }
        let clearedCount = pasteboard.clearContents()
        if pasteboard.writeObjects([item]) { return true }
        // Restore only our still-empty revision. Never restore over a later copy.
        if pasteboard.changeCount == clearedCount, (pasteboard.types ?? []).isEmpty {
            let original = NSPasteboardItem()
            for (type, data) in input.representations { original.setData(data, forType: .init(type)) }
            _ = pasteboard.writeObjects([original])
        }
        return false
    }
}

/// Serial native decoding bounds parallel work when the user copies rapidly.
actor ClipboardImageEncoder {
    func optimize(_ input: Data, maxDimension: Int) -> Data? {
        guard !Task.isCancelled, !input.isEmpty, input.count <= ClipboardImageOptimizationTransaction.maxBytes,
              let source = CGImageSourceCreateWithData(input as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000_000 / height,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(4096, max(64, maxDimension))
              ] as CFDictionary), !Task.isCancelled else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled,
              output.length > 0, output.length < input.count else { return nil }
        return output as Data
    }
}
#endif

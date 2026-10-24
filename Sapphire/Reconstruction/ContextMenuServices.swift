#if !SAPPHIRE_FULL_BUILD
import AppKit

struct SelectionServiceConfiguration: Equatable {
    var enabled = false
    var stripLinks = false
    var stripEmojis = false
    var stripListMarkers = false
    var customTrackingParameters: [String] = []
}

enum SelectionServiceAction: String { case cleanText, cleanURL }

enum SelectionServicePolicy {
    static let maximumBytes = 65_536
    static func transform(_ text: String, action: SelectionServiceAction, configuration: SelectionServiceConfiguration) -> String? {
        guard configuration.enabled, !text.isEmpty, text.utf8.count <= maximumBytes,
              !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        switch action {
        case .cleanText:
            return PlainTextSanitizer.sanitize(text, stripLinks: configuration.stripLinks,
                stripEmojis: configuration.stripEmojis, stripListMarkers: configuration.stripListMarkers)
        case .cleanURL:
            guard configuration.customTrackingParameters.count <= 256,
                  configuration.customTrackingParameters.allSatisfy({ $0.utf8.count <= 128 }) else { return nil }
            // Match the clipboard cleaner's single HTTP(S) URL semantics. Never
            // interpret arbitrary selected text as a path, shell command or URL to open.
            guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  let url = URLComponents(string: text),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty else { return nil }
            return ClipboardURLCleaner.clean(text, customParameters: configuration.customTrackingParameters)
        }
    }
}

/// One public Services provider. Continuity's public registration delegates here;
/// assigning a second NSApp.servicesProvider would silently replace these methods.
@MainActor
final class SystemEnhanceContextMenu: NSObject {
    static let shared = SystemEnhanceContextMenu(configuration: {
        let settings = SettingsModel.shared.current
        return SelectionServiceConfiguration(enabled: settings.systemEnhanceServicesEnabled,
            stripLinks: settings.systemEnhancePasteAsPlainStripLinks,
            stripEmojis: settings.systemEnhancePasteAsPlainStripEmojis,
            stripListMarkers: settings.systemEnhancePasteAsPlainStripListMarkers,
            customTrackingParameters: settings.clipboardCleanURLCustomParams)
    })
    private let configuration: () -> SelectionServiceConfiguration
    init(configuration: @escaping () -> SelectionServiceConfiguration) { self.configuration = configuration; super.init() }
    func installIfNeeded() {
        guard (NSApp.servicesProvider as? SystemEnhanceContextMenu) !== self else { return }
        NSApp.servicesProvider = self
    }
    @objc(sapphireCleanSelectedText:userData:error:)
    func cleanSelectedText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.cleanText, pasteboard: pasteboard, error: error)
    }
    @objc(sapphireCleanSelectedURL:userData:error:)
    func cleanSelectedURL(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.cleanURL, pasteboard: pasteboard, error: error)
    }
    private func perform(_ action: SelectionServiceAction, pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        error.pointee = nil
        let config = configuration()
        guard config.enabled else { error.pointee = "Enable Selection Services in Sapphire’s System settings first."; return }
        // Never accept a request targeting a user's persistent system board.
        guard ![NSPasteboard.Name.general, .find, .font, .ruler, .drag].contains(pasteboard.name) else {
            error.pointee = "A private service-selection pasteboard is required."; return
        }
        let revision = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              !items[0].types.contains(.init("org.nspasteboard.ConcealedType")),
              !items[0].types.contains(.init("org.nspasteboard.TransientType")),
              let data = items[0].data(forType: .string), data.count <= SelectionServicePolicy.maximumBytes,
              let text = String(data: data, encoding: .utf8),
              let result = SelectionServicePolicy.transform(text, action: action, configuration: config) else {
            error.pointee = "Select one unmarked text item up to 64 KiB; URL cleanup needs one HTTP(S) URL without surrounding spaces."; return
        }
        // A promised-data provider can run while data is materialized. Recheck
        // configuration and revision before replacing the Services board.
        guard configuration() == config, pasteboard.changeCount == revision else {
            error.pointee = "The selection or Sapphire settings changed. Try the service again."; return
        }
        let item = NSPasteboardItem()
        guard item.setString(result, forType: .string) else { error.pointee = "Could not encode the result."; return }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { error.pointee = "Could not return the result to the requesting app."; return }
    }
}
#endif

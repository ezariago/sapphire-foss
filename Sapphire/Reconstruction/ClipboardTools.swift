#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

@MainActor
enum ClipboardSyntheticInput {
    static func key(_ code: CGKeyCode, flags: CGEventFlags = .maskCommand) {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SapphireSyntheticEventMarker.plainTextPaste)
            event.post(tap: .cghidEventTap)
        }
    }
}

@MainActor
final class ClipboardAutoClearManager {
    static let shared = ClipboardAutoClearManager()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var monitor: PasteboardChangeMonitor.Token?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var expiry = ClipboardExpiryPolicy(changeCount: NSPasteboard.general.changeCount, now: ProcessInfo.processInfo.systemUptime)
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] config in self?.configure(config.clipboardAutoClearEnabled) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let settings = SettingsModel.shared.current
                if settings.clipboardAutoClearEnabled && settings.clipboardAutoClearOnSleep { self?.clearNow() }
            }
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let settings = SettingsModel.shared.current
                if settings.clipboardAutoClearEnabled && settings.clipboardAutoClearOnLock { self?.clearNow() }
            }
        }
    }
    private func configure(_ enabled: Bool) {
        if enabled && monitor == nil {
            expiry = ClipboardExpiryPolicy(changeCount: NSPasteboard.general.changeCount, now: ProcessInfo.processInfo.systemUptime)
            monitor = PasteboardChangeMonitor.shared.subscribe(interval: 0.2) { [weak self] count in
                self?.expiry.observe(count, now: ProcessInfo.processInfo.systemUptime)
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !enabled {
            if let monitor { PasteboardChangeMonitor.shared.unsubscribe(monitor) }; monitor = nil
            timer?.invalidate(); timer = nil
        }
    }
    private func tick() {
        let settings = SettingsModel.shared.current
        guard settings.clipboardAutoClearEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        expiry.observe(NSPasteboard.general.changeCount, now: now)
        if expiry.shouldClear(now: now, interval: settings.clipboardAutoClearInterval) { clearNow(expectedCount: expiry.changeCount) }
    }
    private func clearNow(expectedCount: Int? = nil) {
        let expected = expectedCount ?? NSPasteboard.general.changeCount
        PasteboardLane.shared.write { pasteboard in
            guard pasteboard.changeCount == expected, !(pasteboard.types ?? []).isEmpty else { return false }
            pasteboard.clearContents()
            return true
        }
    }
    func stop() {
        configure(false); subscription = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }; sleepObserver = nil
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }; lockObserver = nil
    }
}

@MainActor
final class CleanURLManager {
    static let shared = CleanURLManager()
    private var subscription: AnyCancellable?
    private var monitor: PasteboardChangeMonitor.Token?
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] config in
            guard let self else { return }
            if config.clipboardCleanURLEnabled && config.clipboardCleanURLAutoClean && self.monitor == nil {
                self.monitor = PasteboardChangeMonitor.shared.subscribe(interval: 0.2, priority: -10) { [weak self] _ in self?.cleanClipboardLinkNow() }
            } else if !(config.clipboardCleanURLEnabled && config.clipboardCleanURLAutoClean), let monitor = self.monitor {
                PasteboardChangeMonitor.shared.unsubscribe(monitor); self.monitor = nil
            }
        }
    }
    func cleanClipboardLinkNow() {
        let config = SettingsModel.shared.current
        guard config.clipboardCleanURLEnabled else { return }
        let parameters = config.clipboardCleanURLCustomParams
        let expected = NSPasteboard.general.changeCount
        PasteboardLane.shared.write { pasteboard in
            let plainTypes: Set<NSPasteboard.PasteboardType> = [.string, .init("public.utf16-external-plain-text"), .init("NSStringPboardType")]
            guard pasteboard.changeCount == expected,
                  (pasteboard.pasteboardItems?.count ?? 0) == 1,
                  Set(pasteboard.types ?? []).isSubset(of: plainTypes),
                  let text = pasteboard.string(forType: .string) else { return false }
            let cleaned = ClipboardURLCleaner.clean(text, customParameters: parameters)
            guard cleaned != text else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(cleaned, forType: .string)
        }
    }
    func stopPolling() {
        if let monitor { PasteboardChangeMonitor.shared.unsubscribe(monitor) }; monitor = nil
        subscription = nil
    }
}

private final class ClipboardPickerPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor
final class ClipboardPickerManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ClipboardPickerManager()
    @Published var query = ""
    @Published var selected: String?
    private var panel: NSPanel?
    private var target: NSRunningApplication?
    private var subscription: AnyCancellable?
    private override init() {
        super.init()
        subscription = SettingsModel.shared.$settings
            .map { PickerConfiguration(enabled: $0.clipboardPickerEnabled, shortcut: $0.clipboardPickerShortcut) }
            .removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.registerShortcut() }
    }
    private struct PickerConfiguration: Equatable { let enabled: Bool; let shortcut: KeyboardShortcut }
    private func registerShortcut() {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] config in
            guard config.clipboardPickerEnabled else { return [] }
            return [.init(identifier: ShortcutIdentifier.clipboardPicker, shortcut: config.clipboardPickerShortcut, perform: { self?.presentPicker() })]
        }, reportUnavailable: { _ in }), named: "FOSSClipboardPicker")
        if !SettingsModel.shared.current.clipboardPickerEnabled { dismiss() }
    }
    func presentPicker() {
        guard SettingsModel.shared.current.clipboardPickerEnabled else { return }
        if panel != nil { dismiss(); return }
        target = NSWorkspace.shared.frontmostApplication
        query = ""
        selected = ClipboardManager.shared.recentItems.first?.id
        ClipboardManager.shared.beginHighPriorityMonitoring()
        let panel = ClipboardPickerPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Clipboard History"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ClipboardPickerView(manager: self))
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    func choose(_ item: ClipboardItem, paste: Bool) {
        let target = target
        ClipboardManager.shared.copyItem(item) { [weak self] success in
            guard success else { return }
            self?.dismiss()
            guard paste, let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                ClipboardSyntheticInput.key(9)
            }
        }
    }
    func dismiss() {
        guard let current = panel else { return }
        panel = nil
        current.orderOut(nil); current.contentView = nil; current.close()
        ClipboardManager.shared.endHighPriorityMonitoring()
    }
    func windowWillClose(_ notification: Notification) { dismiss() }
    func stopMonitoring() {
        dismiss(); subscription = nil
        KeyboardShortcutManager.shared.unregisterExternalShortcutProvider(named: "FOSSClipboardPicker")
    }
}

private struct ClipboardPickerView: View {
    @ObservedObject var manager: ClipboardPickerManager
    @ObservedObject private var history = ClipboardManager.shared
    private var matches: [ClipboardItem] {
        Array(history.recentItems.filter { manager.query.isEmpty || $0.preview.localizedCaseInsensitiveContains(manager.query) || ($0.textContent?.localizedCaseInsensitiveContains(manager.query) ?? false) }.prefix(300))
    }
    private var selected: ClipboardItem? { matches.first { $0.id == manager.selected } }
    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard history", text: $manager.query).textFieldStyle(.roundedBorder).padding()
            HSplitView {
                List(selection: $manager.selected) {
                    ForEach(matches) { item in
                        HStack {
                            Image(systemName: item.kind == .text ? "doc.text" : item.kind == .image ? "photo" : "doc")
                            Text(item.preview).lineLimit(2)
                            if item.isPinned { Image(systemName: "pin.fill") }
                        }
                        .tag(item.id)
                        .onTapGesture(count: 2) { manager.choose(item, paste: true) }
                    }
                }.frame(minWidth: 300)
                ClipboardPreviewPane(item: selected).frame(minWidth: 280)
            }
            HStack {
                Text("\(matches.count) items").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { manager.dismiss() }.keyboardShortcut(.cancelAction)
                Button("Copy") { if let selected { manager.choose(selected, paste: false) } }.disabled(selected == nil)
                Button("Paste") { if let selected { manager.choose(selected, paste: true) } }
                    .keyboardShortcut(.defaultAction).disabled(selected == nil)
            }.padding()
        }
        .frame(minWidth: 760, minHeight: 480)
        .onChange(of: manager.query) { _, _ in manager.selected = matches.first?.id }
    }
}
#endif

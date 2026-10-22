#if !SAPPHIRE_FULL_BUILD
import SwiftUI
import AppKit
import UserNotifications

struct PhoneNotificationCard: View {
    let entry: PhoneNotification
    var showsHeader = true
    @ObservedObject private var bridge = ContinuityManager.shared.notificationBridge
    @State private var replyAction: PhoneNotification.Action?
    @State private var reply = ""
    @FocusState private var isReplyFocused: Bool
    @State private var ownsNotchFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack {
                    Label(entry.appName, systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if entry.clearable { PhoneNotificationDismissButton(entry: entry) }
                }
            }
            if !entry.title.isEmpty { Text(entry.title).font(.headline).lineLimit(2) }
            if !entry.text.isEmpty { Text(entry.text).font(.subheadline).lineLimit(5).textSelection(.enabled) }
            if !entry.actions.isEmpty {
                HStack {
                    ForEach(entry.actions) { action in
                        Button(action.title) {
                            if action.allowsReply { replyAction = action }
                            else { ReconstructedPhoneLink.shared.notificationCommand(entry, action: action, reply: nil) }
                        }.font(.caption)
                    }
                }
            }
            if let action = replyAction {
                HStack {
                    TextField("Reply", text: $reply)
                        .textFieldStyle(.roundedBorder)
                        .focused($isReplyFocused)
                        .onSubmit { sendReply(action) }
                        .onAppear {
                            if !showsHeader {
                                bridge.composingNotificationID = entry.id
                                requestNotchFocus()
                            }
                            // Focus after SwiftUI has attached the new field to
                            // the panel, which has just become keyable.
                            DispatchQueue.main.async { isReplyFocused = true }
                        }
                        .onChange(of: isReplyFocused) { _, focused in
                            if focused { requestNotchFocus() }
                            else { releaseNotchFocus() }
                        }
                        .onDisappear { finishReplyEditing() }
                    Button("Send") { sendReply(action) }
                        .disabled(!canSendReply)
                    Button("Cancel") { closeReply() }
                }
            }
            if bridge.actionKey == entry.key, !bridge.actionStatus.isEmpty {
                Text(bridge.actionStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(bridge.actionRequestID != nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(entry.id)
        .onDisappear { finishReplyEditing() }
    }

    private var canSendReply: Bool {
        !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reply.utf8.count <= 4000 && bridge.actionRequestID == nil
    }

    private func requestNotchFocus() {
        guard !showsHeader, !ownsNotchFocus,
              let appDelegate = NSApp.delegate as? AppDelegate else { return }
        ownsNotchFocus = true
        appDelegate.makeNotchWindowFocusable()
    }

    private func releaseNotchFocus() {
        guard ownsNotchFocus else { return }
        ownsNotchFocus = false
        (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
    }

    private func finishReplyEditing() {
        isReplyFocused = false
        if bridge.composingNotificationID == entry.id { bridge.composingNotificationID = nil }
        releaseNotchFocus()
    }

    private func closeReply() {
        finishReplyEditing()
        replyAction = nil
        reply = ""
    }

    private func sendReply(_ action: PhoneNotification.Action) {
        guard canSendReply else { return }
        ReconstructedPhoneLink.shared.notificationCommand(entry, action: action, reply: reply)
        closeReply()
    }
}

struct PhoneNotificationDismissButton: View {
    let entry: PhoneNotification
    @ObservedObject private var bridge = ContinuityManager.shared.notificationBridge

    var body: some View {
        Button { ReconstructedPhoneLink.shared.notificationCommand(entry, action: nil, reply: nil) } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 14))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(bridge.actionRequestID != nil)
        .help("Dismiss on phone")
        .accessibilityLabel("Dismiss on phone")
    }
}

struct PhoneNotificationsSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var bridge = ContinuityManager.shared.notificationBridge

    var body: some View {
        GroupBox("Phone notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show phone notifications on Mac", isOn: $settings.settings.continuityNotifications)
                Text("On Android, enable notification sharing and allow Sapphire notification access. Only the paired phone can send notifications over the encrypted connection. Android may redact sensitive content.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Include low-priority notifications", isOn: $settings.settings.continuityNotificationsGeneral)
                Toggle("Include Android system notifications", isOn: $settings.settings.continuityNotificationsSystem)
                Toggle("Also show macOS notification banners", isOn: $settings.settings.continuityNotificationsAsBanners)
                    .onChange(of: settings.settings.continuityNotificationsAsBanners) { _, enabled in
                        if enabled {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }
                    }
                if !bridge.actionStatus.isEmpty { Text(bridge.actionStatus).font(.caption).foregroundStyle(.secondary) }
                if bridge.notifications.isEmpty {
                    Text("No shared phone notifications. New notifications appear in the notch; existing ones refresh here when connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(bridge.notifications) { entry in
                    Divider()
                    PhoneNotificationCard(entry: entry)
                }
            }.padding(8)
        }
    }
}
#endif

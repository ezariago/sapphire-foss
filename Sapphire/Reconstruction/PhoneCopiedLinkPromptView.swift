#if !SAPPHIRE_FULL_BUILD
import SwiftUI
struct PhoneCopiedLinkPromptView: View {
    let prompt: PhoneCopiedLinkPrompt
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open link from phone?").font(.caption).fontWeight(.semibold)
                Text(prompt.url.host ?? "Web link").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Open") { ReconstructedPhoneLink.shared.openCopiedLink(id: prompt.id) }.buttonStyle(.bordered)
            Button { ReconstructedPhoneLink.shared.dismissCopiedLink(id: prompt.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss copied link")
        }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 340)
            .help(prompt.url.absoluteString)
    }
}
#endif

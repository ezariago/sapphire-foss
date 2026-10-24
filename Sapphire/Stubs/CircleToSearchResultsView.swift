#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct CircleToSearchResultsView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject private var session = CircleToSearchManager.shared.session
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screen text search").font(.headline)
            Text("Recognizes text locally. Search Google sends only the text below to your browser; no image is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Review or edit recognized text", text: $session.query, axis: .vertical).lineLimit(2...5)
            Text(session.status).font(.caption).foregroundStyle(.secondary)
            if session.busy { ProgressView() }
            HStack {
                Button("Select region…") { CircleToSearchManager.shared.selectRegion() }.disabled(session.busy)
                Button("Search Google") { session.search() }
                    .disabled(session.busy || RegionTextSearchPolicy.query(session.query) == nil)
                Button("Clear") { session.clear() }
            }
        }.padding().frame(width: 360)
    }
}
#endif

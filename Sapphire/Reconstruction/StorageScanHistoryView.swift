#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct StorageScanHistoryView: View {
    let history: [ScanResult]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History for this folder and scan mode").font(.headline)
            Text("Latest 30 recorded scans. Accounted bytes are scope estimates; moving files to Trash does not reclaim disk space. Older records may have no Trash accounting.")
                .font(.caption).foregroundStyle(.secondary)
            if history.isEmpty { Text("No completed scans recorded for this folder and mode.").foregroundStyle(.secondary) }
            ForEach(Array(history.suffix(30).reversed().enumerated()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 5) {
                    Text(timestamp(record.timestamp)).font(.subheadline.weight(.semibold))
                    LabeledContent("Accounted bytes", value: max(0, record.totalScanned).formatted(.byteCount(style: .file)))
                    if let moved = record.bytesMovedToTrash {
                        LabeledContent("Moved to Trash since prior recorded scan", value: max(0, moved).formatted(.byteCount(style: .file)))
                    }
                    if record.duration.isFinite, record.duration >= 0, record.duration <= 86400 {
                        LabeledContent("Scan duration", value: record.duration.formatted(.number.precision(.fractionLength(1))) + " s")
                    }
                }.font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            if history.count > 30 { Text("Showing 30 of \(history.count) records in this scope.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func timestamp(_ date: Date) -> String {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, (-62_135_596_800...253_402_300_799).contains(seconds) else { return "Unknown timestamp" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
#endif

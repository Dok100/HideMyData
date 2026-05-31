import SwiftUI

struct ModelSourceCard: View {
    var body: some View {
        Link(destination: PIIDetector.modelURL) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Modellquelle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(PIIDetector.modelRepoID)
                        .font(.callout.monospaced())
                        .foregroundStyle(.primary)

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Hugging Face · ca. 1,5 GB · nach dem Download lokal auf deinem Mac")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.quinary, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("\(PIIDetector.modelURL.absoluteString) im Browser öffnen")
        .accessibilityLabel("Modellquelle: \(PIIDetector.modelRepoID), von Hugging Face, etwa 1,5 Gigabyte groß und nach dem Download lokal auf deinem Mac. Öffnet sich im Browser.")
    }
}

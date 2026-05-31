import SwiftUI

struct FirstRunPhase: View {
    @Bindable var detector: PIIDetector
    @State private var progressStartedAt: Date = .now

    var body: some View {
        Group {
            switch detector.phase {
            case .needsDownload:
                downloadAction
            case .downloading(let downloaded, let total):
                downloadProgress(downloaded: downloaded, total: total)
            case .failed(let message):
                downloadFailure(message: message)
            default:
                EmptyView()
            }
        }
    }

    private var downloadAction: some View {
        Button(action: beginDownload) {
            Label("Modell herunterladen", systemImage: "arrow.down.circle.fill")
                .frame(minWidth: 220)
                .padding(.vertical, 4)
        }
        .controlSize(.large)
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
    }

    private func downloadProgress(downloaded: Int64, total: Int64) -> some View {
        VStack(spacing: 10) {
            if total > 0 {
                ProgressView(value: Double(downloaded), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(width: 320)

                TimelineView(.periodic(from: progressStartedAt, by: 1)) { context in
                    Text(progressText(downloaded: downloaded, total: total, now: context.date))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Download wird vorbereitet…")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func downloadFailure(message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            Button("Erneut versuchen", systemImage: "arrow.clockwise", action: beginDownload)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    private func beginDownload() {
        progressStartedAt = .now
        Task {
            await detector.startDownload()
        }
    }

    private func progressText(downloaded: Int64, total: Int64, now: Date) -> String {
        let downloadedGB = Double(downloaded) / 1_000_000_000
        let totalGB = Double(total) / 1_000_000_000
        let elapsed = Duration.seconds(now.timeIntervalSince(progressStartedAt))
            .formatted(.time(pattern: .minuteSecond))

        return "\(downloadedGB.formatted(.number.precision(.fractionLength(1)))) / \(totalGB.formatted(.number.precision(.fractionLength(1)))) GB  ·  \(elapsed)"
    }
}

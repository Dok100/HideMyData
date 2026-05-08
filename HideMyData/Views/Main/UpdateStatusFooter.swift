import SwiftUI

struct UpdateStatusFooter: View {
    @Environment(UpdaterModel.self) private var updater

    var body: some View {
        HStack(spacing: 8) {
            Text("v\(updater.currentVersion)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            switch updater.status {
            case .unknown:
                Button("Nach Updates suchen", action: updater.checkForUpdates)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            case .upToDate:
                Text("Aktuell")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            case .updateAvailable(let version):
                Button {
                    updater.installUpdate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Auf v\(version) aktualisieren")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

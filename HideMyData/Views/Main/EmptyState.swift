import SwiftUI
internal import UniformTypeIdentifiers

struct EmptyState: View {
    @Binding var inputMode: InputMode
    @Bindable var recents: RecentsStore
    @Binding var recentsEnabled: Bool
    let onOpenClipboardAnonymizer: () -> Void
    let onOpenPDF: () -> Void
    let onOpenImage: () -> Void
    let onDropFile: (URL) -> Void
    let onOpenRecent: (RecentItem) -> Void
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            dropZone
                .padding(.horizontal, 60)

            Spacer(minLength: 36)

            if !recents.items.isEmpty {
                RecentsRow(store: recents, onOpen: onOpenRecent)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer().frame(height: 18)
            }

            privacyToggle
                .padding(.horizontal, 36)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .center)

            UpdateStatusFooter()
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDropFile(url)
            return true
        } isTargeted: { hovering in
            withAnimation(.smooth(duration: 0.20)) { isTargeted = hovering }
        }
    }

    @ViewBuilder
    private var dropZone: some View {
        VStack(spacing: 28) {
            Text("INKOGNITO")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(4.0)
                .foregroundStyle(Color.primary.opacity(0.5))

            VStack(spacing: 12) {
                Text(isTargeted ? "Zum Öffnen ablegen" : "Anonymisieren. Direkt auf deinem Mac.")
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)

                Text("Ziehe ein PDF oder Bild hierher. Inkognito erkennt sensible Daten, zeigt sie zur Prüfung an und schwärzt sie dauerhaft.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 460)
                    .opacity(isTargeted ? 0 : 1)

                Text("Keine Cloud. Keine Übertragung. Alles bleibt lokal.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .opacity(isTargeted ? 0 : 1)
            }
            .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 16) {
                documentActionCard
                clipboardActionCard
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 36)
        .frame(maxWidth: 760)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.90),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.70)) : AnyShapeStyle(Color.black.opacity(0.08)),
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 1.6 : 1,
                        dash: isTargeted ? [] : []
                    )
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .scaleEffect(isTargeted ? 1.015 : 1.0)
        .animation(.smooth(duration: 0.22), value: isTargeted)
    }

    private var documentActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Dokument anonymisieren")
                    .font(.system(size: 15, weight: .semibold))
            }

            Text("Öffne ein PDF oder Bild und prüfe erkannte sensible Stellen vor dem finalen Schwärzen.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Format wählen")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)

                InputTabSegmented(inputMode: $inputMode)
                    .fixedSize()

                Text(modeSelectionHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
            }

            Button(action: openAction) {
                Label(openButtonTitle, systemImage: openIcon)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var clipboardActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Kopierten Text schützen")
                    .font(.system(size: 15, weight: .semibold))
            }

            Text("Anonymisiere sensible Inhalte, bevor du sie in KI-Chatbots, E-Mails oder Dokumente einfügst.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Schnellzugriff")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("⌘ ⇧ A öffnet die Vorschau für kopierten Text.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onOpenClipboardAnonymizer) {
                Label("Kopierten Text anonymisieren", systemImage: "arrow.left.arrow.right.square")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var openIcon: String {
        switch inputMode {
        case .pdf: "doc.badge.plus"
        case .image: "photo.badge.plus"
        }
    }

    private var openButtonTitle: String {
        switch inputMode {
        case .pdf: "PDF öffnen"
        case .image: "Bild öffnen"
        }
    }

    private var modeSelectionHint: String {
        switch inputMode {
        case .pdf: "PDF-Dokument ausgewählt"
        case .image: "Bilddatei ausgewählt"
        }
    }

    private var openAction: () -> Void {
        switch inputMode {
        case .pdf: onOpenPDF
        case .image: onOpenImage
        }
    }

    @ViewBuilder
    private var privacyToggle: some View {
        Toggle(isOn: $recentsEnabled) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuletzt verwendet speichern")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Dateiverweise und Vorschaubilder lokal auf diesem Mac behalten.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: 420, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.8)
        )
    }

}

import SwiftUI
internal import UniformTypeIdentifiers

struct EmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var inputMode: InputMode
    @Bindable var recents: RecentsStore
    let onOpenClipboardAnonymizer: () -> Void
    let onOpenPDF: () -> Void
    let onOpenImage: () -> Void
    let onDropFile: (URL) -> Void
    let onOpenRecent: (RecentItem) -> Void
    @State private var isTargeted: Bool = false

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 44)

                    dropZone
                        .padding(.horizontal, 40)

                    Spacer().frame(height: 28)

                    recentsSection
                        .padding(.horizontal, 36)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    UpdateStatusFooter()
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
            }

            if isTargeted {
                dragOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .allowsHitTesting(false)
            }
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

    private var panelFill: Color {
        SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme)
    }

    private var cardFill: Color {
        SurfaceVisualSemantics.secondaryPanelFill(colorScheme: colorScheme)
    }

    private var cardBorder: Color {
        SurfaceVisualSemantics.secondaryPanelBorder(colorScheme: colorScheme)
    }

    private var badgeFill: Color {
        SurfaceVisualSemantics.secondaryPanelFill(colorScheme: colorScheme)
    }

    private var badgeBorder: Color {
        SurfaceVisualSemantics.secondaryPanelBorder(colorScheme: colorScheme)
    }

    private var helperCapsuleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    private var dropHintFill: Color {
        colorScheme == .dark ? Color.accentColor.opacity(0.10) : Color.accentColor.opacity(0.06)
    }

    private var dropHintBorder: Color {
        isTargeted
            ? Color.accentColor.opacity(0.80)
            : Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.26)
    }

    private let cardHeaderHeight: CGFloat = 34
    private let cardDescriptionHeight: CGFloat = 74
    private let cardDetailHeight: CGFloat = 128

    @ViewBuilder
    private var dropZone: some View {
        VStack(spacing: 28) {
            Text("INKOGNITO")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(4.0)
                .foregroundStyle(Color.primary.opacity(0.58))

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Keine Cloud. Keine Übertragung. Alles bleibt lokal.")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.primary.opacity(0.66))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(badgeFill, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(badgeBorder, lineWidth: 0.8)
            )

            VStack(spacing: 12) {
                Text(isTargeted ? "Jetzt zum Öffnen ablegen" : "Anonymisieren. Direkt auf deinem Mac.")
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)

                Text("Öffne ein Dokument oder anonymisiere kopierten Text. Inkognito arbeitet vollständig lokal auf deinem Mac, ohne Cloud und ohne Datenübertragung.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 460)
                    .opacity(isTargeted ? 0 : 1)
            }
            .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 16) {
                documentActionCard
                clipboardActionCard
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 36)
        .frame(maxWidth: 860)
        .background(
            panelFill,
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Dokument öffnen")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(minHeight: cardHeaderHeight, alignment: .topLeading)

            Text("PDF oder Bild öffnen, sensible Inhalte prüfen und geschützt exportieren.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: cardDescriptionHeight, alignment: .topLeading)

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

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Datei hier ablegen")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Ziehe PDF oder Bild direkt in die Startfläche.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isTargeted {
                        Text("Loslassen zum direkten Öffnen")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(dropHintFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            dropHintBorder,
                            style: StrokeStyle(lineWidth: isTargeted ? 1.4 : 1, dash: [7, 6])
                        )
                )
            }
            .frame(minHeight: cardDetailHeight, alignment: .topLeading)

            Spacer(minLength: 0)

            Button(action: openAction) {
                Label(openButtonTitle, systemImage: openIcon)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
        .padding(18)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor.opacity(0.72) : cardBorder,
                    style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 0.9, dash: isTargeted ? [7, 7] : [4, 6])
                )
        )
    }

    private var clipboardActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.green)
                Text("Zwischenablage schützen")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(minHeight: cardHeaderHeight, alignment: .topLeading)

            Text("Kopierten Text anonymisieren, sicher weitergeben und bei Bedarf wieder zurückführen.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: cardDescriptionHeight, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Schnellzugriff")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    ShortcutKey(text: "⌘")
                    ShortcutKey(text: "⇧")
                    ShortcutKey(text: "A")

                    Text("öffnet die Textansicht sofort.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: cardDetailHeight, alignment: .topLeading)

            Spacer(minLength: 0)

            Button(action: onOpenClipboardAnonymizer) {
                Label("Text aus Zwischenablage öffnen", systemImage: "arrow.left.arrow.right.square")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
        .padding(18)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.8)
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
        case .pdf: "Format: PDF"
        case .image: "Format: Bild"
        }
    }

    private var openAction: () -> Void {
        switch inputMode {
        case .pdf: onOpenPDF
        case .image: onOpenImage
        }
    }

    @ViewBuilder
    private var recentsSection: some View {
        if recents.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Zuletzt verwendet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)

                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StatusVisualSemantics.trust)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Noch keine zuletzt verwendeten Dateien")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Zuletzt geöffnete PDFs und Bilder erscheinen hier für einen schnellen Wiedereinstieg.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 0.8)
                )
            }
        } else {
            RecentsRow(store: recents, onOpen: onOpenRecent)
        }
    }

    private var dragOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("PDF oder Bild hier ablegen")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Inkognito öffnet die Datei direkt zur Prüfung.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: 560)
            .background(panelFill.opacity(colorScheme == .dark ? 0.98 : 0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 1.8, dash: [10, 9]))
            )
            .shadow(color: .black.opacity(0.10), radius: 22, y: 8)
        }
    }

}

private struct ShortcutKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
    }
}

import SwiftUI

struct FloatingToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    let detector: PIIDetector
    @Bindable var pdfRedactor: PDFRedactor
    @Bindable var imageRedactor: ImageRedactor
    let customPatternsCount: Int
    let inputMode: InputMode
    let onManagePatterns: () -> Void
    let onShowDiagnostics: () -> Void
    let onAnonymizeClipboard: () -> Void
    let onOpenRequest: () -> Void
    let onSaveRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            primaryActions
            Divider()
                .frame(height: 26)
            editingControls
            Divider()
                .frame(height: 26)
            styleControls
            Divider()
                .frame(height: 26)
            utilityMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SurfaceVisualSemantics.elevatedPanelBorder(colorScheme: colorScheme), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .controlSize(.large)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var primaryActions: some View {
        HStack(spacing: 8) {
            openButton
            detectButton
            saveButton
        }
    }

    @ViewBuilder
    private var openButton: some View {
        Button(action: onOpenRequest) {
            Label("Öffnen", systemImage: openIcon)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("o", modifiers: [.command])
        .help("Öffnen  ⌘O")
    }

    @ViewBuilder
    private var detectButton: some View {
        Button(action: detect) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, isActive: isDetecting)
                Text("Erkennen")
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!detector.isReady || !canDetect)
        .keyboardShortcut("d", modifiers: [.command])
        .help("PII automatisch erkennen  ⌘D")
    }

    @ViewBuilder
    private var saveButton: some View {
        Button(action: saveAction) {
            Label(saveButtonTitle, systemImage: "square.and.arrow.down")
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .disabled(!hasFile)
        .keyboardShortcut("s", modifiers: [.command])
        .help(saveHelpText)
    }

    @ViewBuilder
    private var editingControls: some View {
        HStack(spacing: 8) {
            modeSegmented
        }
    }

    @ViewBuilder
    private var styleControls: some View {
        HStack(spacing: 8) {
            styleSegmented
        }
    }

    @ViewBuilder
    private var utilityMenu: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Label("Einstellungen", systemImage: "gearshape")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .help("Einstellungen öffnen  ⌘,")

            Menu {
                Button(action: onManagePatterns) {
                    Label(customPatternsCount > 0 ? "Regeln verwalten (\(customPatternsCount))" : "Regeln verwalten",
                          systemImage: "text.badge.plus")
                }

                Button(action: onAnonymizeClipboard) {
                    Label("Zwischenablage anonymisieren", systemImage: "doc.on.clipboard")
                }
                .disabled(!detector.isReady || isDetecting)

                Button(action: onShowDiagnostics) {
                    Label("Diagnose öffnen", systemImage: "ladybug")
                }
                .disabled(!hasDiagnostics)

                Divider()

                Button(role: .destructive, action: clearAction) {
                    Label("Alle Schwärzungen entfernen", systemImage: "xmark.circle")
                }
                .disabled(!hasRedactions || isDetecting)
            } label: {
                Label("Werkzeuge", systemImage: "ellipsis.circle")
                    .padding(.horizontal, 4)
            }
            .menuStyle(.button)
            .controlSize(.regular)
            .help("Sekundäre Werkzeuge und Hilfsfunktionen")
        }
    }

    @ViewBuilder
    private var styleSegmented: some View {
        GlassSegmented(
            selection: styleBinding,
            items: RedactionStyle.allCases.map {
                .init(value: $0, image: $0.systemImage, label: $0.displayName, help: "\($0.displayName)-Schwärzung")
            }
        )
        .fixedSize()
        .disabled(!detector.isReady || isDetecting)
    }

    @ViewBuilder
    private var modeSegmented: some View {
        GlassSegmented(
            selection: editingModeBinding,
            items: EditingMode.allCases.map {
                .init(value: $0, image: $0.systemImage, label: $0.displayName, help: $0.helpText)
            }
        )
        .fixedSize()
        .disabled(!detector.isReady || !hasFile || isDetecting)
    }

    // MARK: - Mode-aware dispatch

    private var hasFile: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.document != nil
        case .image: imageRedactor.image != nil
        }
    }

    private var canDetect: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.canDetect
        case .image: imageRedactor.canDetect
        }
    }

    private var hasRedactions: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasRedactions
        case .image: imageRedactor.hasRedactions
        }
    }

    private var isDetecting: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.phase == .detecting
        case .image: imageRedactor.phase == .detecting
        }
    }

    private var openIcon: String {
        switch inputMode {
        case .pdf: "doc.badge.plus"
        case .image: "photo.badge.plus"
        }
    }

    private var saveAction: () -> Void {
        onSaveRequest
    }

    private var clearAction: () -> Void {
        switch inputMode {
        case .pdf: pdfRedactor.clearRedactions
        case .image: imageRedactor.clearRedactions
        }
    }

    private func detect() {
        switch inputMode {
        case .pdf: pdfRedactor.detectAndRedact(using: detector)
        case .image: imageRedactor.detectAndRedact(using: detector)
        }
    }

    private var styleBinding: Binding<RedactionStyle> {
        switch inputMode {
        case .pdf: $pdfRedactor.redactionStyle
        case .image: $imageRedactor.redactionStyle
        }
    }

    private var editingModeBinding: Binding<EditingMode> {
        switch inputMode {
        case .pdf: $pdfRedactor.editingMode
        case .image: $imageRedactor.editingMode
        }
    }

    private var saveHelpText: String {
        if hasPendingReview {
            return "Vor dem Speichern alle Treffer prüfen"
        }
        if reviewIsComplete {
            return "Review fertig: geschwärzte Kopie jetzt sicher speichern  ⌘S"
        }
        return "Geschwärzte Kopie speichern  ⌘S"
    }

    private var saveButtonTitle: String {
        reviewIsComplete ? "Sicher exportieren" : "Speichern"
    }

    private var hasPendingReview: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasPendingReview
        case .image: imageRedactor.hasPendingReview
        }
    }

    private var hasReviewFindings: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasReviewFindings
        case .image: imageRedactor.hasReviewFindings
        }
    }

    private var reviewIsComplete: Bool {
        hasFile && hasReviewFindings && !hasPendingReview
    }

    private var hasDiagnostics: Bool {
        switch inputMode {
        case .pdf: !pdfRedactor.debugEntries.isEmpty
        case .image: !imageRedactor.debugEntries.isEmpty
        }
    }
}

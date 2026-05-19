import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
    private static let recentsEnabledKey = "Inkognito.recents.enabled"
    private static let legacyRecentsEnabledKey = "HMD.recents.enabled"

    let detector: PIIDetector
    @Bindable var pdfRedactor: PDFRedactor
    @Bindable var imageRedactor: ImageRedactor
    @Bindable var recents: RecentsStore
    @Bindable var customPatterns: CustomPatternStore
    @Binding var inputMode: InputMode
    @State private var showHome: Bool = false
    @AppStorage(Self.recentsEnabledKey) private var recentsEnabled: Bool = true
    @State private var saveWarningPresented = false
    @State private var customPatternsPresented = false
    @State private var diagnosticsPresented = false
    @State private var clipboardAnonymizerPresented = false
    @State private var reviewUndoNotice: ReviewUndoNotice?
    @State private var presentedIssue: UserFacingIssue?

    private var activeIsEmpty: Bool {
        switch inputMode {
        case .pdf: return pdfRedactor.document == nil
        case .image: return imageRedactor.image == nil
        }
    }

    private var shouldShowEmpty: Bool { showHome || activeIsEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            if shouldShowEmpty {
                EmptyState(
                    inputMode: $inputMode,
                    recents: recents,
                    onOpenClipboardAnonymizer: { clipboardAnonymizerPresented = true },
                    onOpenPDF: openPDFAndAdd,
                    onOpenImage: openImageAndAdd,
                    onDropFile: handleDrop,
                    onOpenRecent: openRecent
                )
            } else {
                workspaceBackdrop
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        HomeButton { showHome = true }

                        Spacer(minLength: 0)

                        FloatingToolbar(
                            detector: detector,
                            pdfRedactor: pdfRedactor,
                            imageRedactor: imageRedactor,
                            customPatternsCount: customPatterns.patterns.count,
                            inputMode: inputMode,
                            onManagePatterns: { customPatternsPresented = true },
                            onShowDiagnostics: { diagnosticsPresented = true },
                            onAnonymizeClipboard: { clipboardAnonymizerPresented = true },
                            onOpenRequest: openCurrentInputType,
                            onSaveRequest: requestSave
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    HStack(alignment: .center, spacing: 14) {
                        WorkflowStepStrip(currentStep: currentWorkflowStep)

                        Spacer(minLength: 0)

                        if inputMode == .pdf, currentPDFPageCount > 1 {
                            PDFPageNavigationBar(
                                currentPageIndex: currentPDFPageIndex,
                                pageCount: currentPDFPageCount,
                                canGoPrevious: pdfRedactor.canGoToPreviousPage,
                                canGoNext: pdfRedactor.canGoToNextPage,
                                onPrevious: pdfRedactor.goToPreviousPage,
                                onNext: pdfRedactor.goToNextPage
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)

                    HStack(spacing: 0) {
                        Group {
                            switch inputMode {
                            case .pdf:
                                DocumentSurface(redactor: pdfRedactor)
                            case .image:
                                ImageDocumentSurface(redactor: imageRedactor)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ReviewSidebar(
                            findings: currentReviewFindings,
                            pendingCount: currentPendingReviewCount,
                            acceptedCount: currentAcceptedReviewCount,
                            rejectedCount: currentRejectedReviewCount,
                            hasProtectedContent: hasProtectedContent,
                            selectedFindingID: currentFocusedFindingID,
                            undoNotice: reviewUndoNotice,
                            exportReport: currentExportReport,
                            onAcceptAll: acceptAllFindings,
                            onSave: requestSave,
                            onDismissUndoNotice: { reviewUndoNotice = nil },
                            onUndoLastDecision: undoLastDecision,
                            onSelect: selectFinding,
                            onAccept: acceptFinding,
                            onReject: rejectFinding,
                            onReopen: reopenFinding
                        )
                        .padding(.trailing, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }
                }
            }

            StatusPill(
                detector: detector,
                pdfRedactor: pdfRedactor,
                imageRedactor: imageRedactor,
                inputMode: inputMode,
                showingDocument: !shouldShowEmpty
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.horizontal, 28)
            .padding(.top, shouldShowEmpty ? 22 : 82)
            .allowsHitTesting(false)
        }
        .onAppear {
            migrateLegacyRecentsPreferenceIfNeeded()
            recents.setEnabled(recentsEnabled)
        }
        .onChange(of: recentsEnabled) { _, enabled in
            recents.setEnabled(enabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showClipboardAnonymizer)) { _ in
            clipboardAnonymizerPresented = true
        }
        .alert("Prüfung erforderlich", isPresented: $saveWarningPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte bestätige oder lehne zuerst alle offenen Treffer ab, bevor du speicherst.")
        }
        .alert(item: $presentedIssue) { issue in
            if let retryAction = issue.retryAction {
                Alert(
                    title: Text(issue.title),
                    message: Text(issue.message),
                    primaryButton: .default(Text(issue.retryLabel ?? "Erneut versuchen"), action: retryAction),
                    secondaryButton: .cancel(Text("OK"))
                )
            } else {
                Alert(
                    title: Text(issue.title),
                    message: Text(issue.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $customPatternsPresented) {
            CustomPatternsSheet(store: customPatterns)
        }
        .sheet(isPresented: $diagnosticsPresented) {
            DiagnosticsSheet(entries: currentDebugEntries)
        }
        .sheet(isPresented: $clipboardAnonymizerPresented) {
            ClipboardAnonymizerSheet(detector: detector)
        }
    }

    private func migrateLegacyRecentsPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.recentsEnabledKey) == nil,
              let legacy = defaults.object(forKey: Self.legacyRecentsEnabledKey) as? Bool else { return }
        recentsEnabled = legacy
        defaults.removeObject(forKey: Self.legacyRecentsEnabledKey)
    }

    @ViewBuilder
    private var workspaceBackdrop: some View {
        ZStack {
            if colorScheme == .dark {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.025),
                        Color.black.opacity(0.10),
                        Color.accentColor.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.black.opacity(0.015),
                        Color.accentColor.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Open actions

    private func openCurrentInputType() {
        switch inputMode {
        case .pdf: openPDFAndAdd()
        case .image: openImageAndAdd()
        }
    }

    private func openPDFAndAdd() {
        switch pdfRedactor.presentOpenPanel() {
        case .cancelled:
            return
        case .failed(let message):
            presentIssue(
                title: "PDF konnte nicht geöffnet werden",
                message: message,
                retryLabel: "Erneut versuchen",
                retryAction: openPDFAndAdd
            )
        case .opened(let url):
            recents.add(url: url, kind: .pdf)
            showHome = false
        }
    }

    private func openImageAndAdd() {
        switch imageRedactor.presentOpenPanel() {
        case .cancelled:
            return
        case .failed(let message):
            presentIssue(
                title: "Bild konnte nicht geöffnet werden",
                message: message,
                retryLabel: "Erneut versuchen",
                retryAction: openImageAndAdd
            )
        case .opened(let url):
            recents.add(url: url, kind: .image)
            showHome = false
        }
    }

    private func handleDrop(_ url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        if type.conforms(to: .pdf) {
            inputMode = .pdf
            if pdfRedactor.loadPDF(from: url) {
                recents.add(url: url, kind: .pdf)
                showHome = false
            } else {
                presentIssue(
                    title: "PDF konnte nicht geladen werden",
                    message: "Die abgelegte Datei „\(url.lastPathComponent)“ konnte nicht gelesen werden. Bitte prüfe, ob sie vollständig ist und wirklich ein PDF enthält."
                )
            }
        } else if type.conforms(to: .image) {
            inputMode = .image
            if imageRedactor.loadImage(from: url) {
                recents.add(url: url, kind: .image)
                showHome = false
            } else {
                presentIssue(
                    title: "Bild konnte nicht geladen werden",
                    message: "Die abgelegte Datei „\(url.lastPathComponent)“ konnte nicht gelesen werden. Bitte prüfe, ob sie vollständig ist und ein unterstütztes Bildformat hat."
                )
            }
        } else {
            presentIssue(
                title: "Datei wird nicht unterstützt",
                message: "Bitte lege ein PDF oder ein Bild ab. Andere Dateitypen kann Inkognito hier noch nicht öffnen."
            )
        }
    }

    private func openRecent(_ item: RecentItem) {
        guard let resolved = recents.resolve(item) else {
            recents.remove(item)
            return
        }
        defer { if resolved.didStartScope { resolved.url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: resolved.url) else {
            recents.remove(item)
            presentIssue(
                title: "Zuletzt verwendete Datei nicht lesbar",
                message: "„\(item.title)“ konnte nicht erneut geladen werden. Der Eintrag wurde aus den zuletzt verwendeten Dateien entfernt."
            )
            return
        }

        switch item.kind {
        case .pdf:
            inputMode = .pdf
            if pdfRedactor.loadPDF(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .pdf)
                showHome = false
            } else {
                presentIssue(
                    title: "Zuletzt verwendetes PDF konnte nicht geöffnet werden",
                    message: "„\(item.title)“ konnte nicht gelesen werden. Bitte öffne die Datei erneut oder wähle eine andere Version."
                )
            }
        case .image:
            inputMode = .image
            if imageRedactor.loadImage(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .image)
                showHome = false
            } else {
                presentIssue(
                    title: "Zuletzt verwendetes Bild konnte nicht geöffnet werden",
                    message: "„\(item.title)“ konnte nicht gelesen werden. Bitte öffne die Datei erneut oder wähle eine andere Version."
                )
            }
        }
    }

    private var currentReviewFindings: [ReviewFinding] {
        switch inputMode {
        case .pdf: pdfRedactor.reviewFindings
        case .image: imageRedactor.reviewFindings
        }
    }

    private var currentPendingReviewCount: Int {
        switch inputMode {
        case .pdf: pdfRedactor.pendingReviewCount
        case .image: imageRedactor.pendingReviewCount
        }
    }

    private var currentAcceptedReviewCount: Int {
        currentReviewFindings.filter { $0.status == .accepted }.count
    }

    private var currentRejectedReviewCount: Int {
        currentReviewFindings.filter { $0.status == .rejected }.count
    }

    private var currentExportReport: ExportValidationReport? {
        switch inputMode {
        case .pdf: pdfRedactor.lastExportReport
        case .image: imageRedactor.lastExportReport
        }
    }

    private var currentFocusedFindingID: UUID? {
        switch inputMode {
        case .pdf: pdfRedactor.focusedFindingID
        case .image: imageRedactor.focusedFindingID
        }
    }

    private var currentWorkflowStep: WorkflowStepStrip.Step {
        if hasPendingReview {
            return .review
        }
        if !hasProtectedContent {
            return currentReviewFindings.isEmpty ? .detect : .review
        }
        switch inputMode {
        case .pdf:
            if pdfRedactor.hasRedactions || !pdfRedactor.reviewFindings.isEmpty {
                return .save
            }
        case .image:
            if imageRedactor.hasRedactions || !imageRedactor.reviewFindings.isEmpty {
                return .save
            }
        }
        return .detect
    }

    private var currentPDFPageCount: Int {
        inputMode == .pdf ? pdfRedactor.pageCount : 0
    }

    private var currentPDFPageIndex: Int {
        inputMode == .pdf ? pdfRedactor.currentPageIndex : 0
    }

    private var hasProtectedContent: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasRedactions
        case .image: imageRedactor.hasRedactions
        }
    }

    private var hasPendingReview: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasPendingReview
        case .image: imageRedactor.hasPendingReview
        }
    }

    private var currentDebugEntries: [DetectionDebugEntry] {
        switch inputMode {
        case .pdf: pdfRedactor.debugEntries
        case .image: imageRedactor.debugEntries
        }
    }

    private func requestSave() {
        guard hasProtectedContent else {
            presentIssue(
                title: "Noch nichts zum Exportieren geschützt",
                message: "Erkenne zuerst sensible Inhalte oder setze mindestens eine manuelle Schwärzung. Erst danach kann Inkognito eine geschützte Kopie exportieren."
            )
            return
        }
        guard !hasPendingReview else {
            saveWarningPresented = true
            return
        }
        switch inputMode {
        case .pdf:
            switch pdfRedactor.save() {
            case .cancelled, .saved:
                return
            case .failed(let message):
                presentIssue(
                    title: "PDF konnte nicht gespeichert werden",
                    message: message,
                    retryLabel: "Erneut versuchen",
                    retryAction: requestSave
                )
            }
        case .image:
            switch imageRedactor.save() {
            case .cancelled, .saved:
                return
            case .failed(let message):
                presentIssue(
                    title: "Bild konnte nicht gespeichert werden",
                    message: message,
                    retryLabel: "Erneut versuchen",
                    retryAction: requestSave
                )
            }
        }
    }

    private func presentIssue(
        title: String,
        message: String,
        retryLabel: String? = nil,
        retryAction: (() -> Void)? = nil
    ) {
        presentedIssue = UserFacingIssue(
            title: title,
            message: message,
            retryLabel: retryLabel,
            retryAction: retryAction
        )
    }

    private func selectFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.selectFinding(id)
        case .image: imageRedactor.selectFinding(id)
        }
    }

    private func acceptFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.acceptFinding(id)
        case .image: imageRedactor.acceptFinding(id)
        }
        showUndoNotice(for: id, verb: "bestätigt")
    }

    private func acceptAllFindings() {
        switch inputMode {
        case .pdf: pdfRedactor.acceptAllFindings()
        case .image: imageRedactor.acceptAllFindings()
        }
    }

    private func rejectFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.rejectFinding(id)
        case .image: imageRedactor.rejectFinding(id)
        }
        showUndoNotice(for: id, verb: "abgelehnt")
    }

    private func reopenFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.reopenFinding(id)
        case .image: imageRedactor.reopenFinding(id)
        }
        reviewUndoNotice = nil
    }

    private func undoLastDecision() {
        guard let findingID = reviewUndoNotice?.findingID else { return }
        reopenFinding(findingID)
    }

    private func showUndoNotice(for id: UUID, verb: String) {
        let snippet = currentReviewFindings.first(where: { $0.id == id })?.snippet ?? "Treffer"
        reviewUndoNotice = ReviewUndoNotice(
            findingID: id,
            title: "Treffer \(verb)",
            detail: snippet
        )
    }

}

private struct ReviewUndoNotice: Equatable {
    let findingID: UUID
    let title: String
    let detail: String
}

private struct DebugInfoButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(16)
        }
    }
}

private struct UserFacingIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retryLabel: String?
    let retryAction: (() -> Void)?
}

private struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let entries: [DetectionDebugEntry]
    @State private var selectedEntryID: DetectionDebugEntry.ID?
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(entries, selection: $selectedEntryID) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(entry.findings.count) Treffer · \(entry.diagnostics.count) Hinweise · \(entry.previewDiagnostics.count) Vorschauzeilen · \(entry.textSourceLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .tag(entry.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedEntry.title)
                                .font(.title3.weight(.semibold))
                            Text(selectedEntry.textSourceLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        debugCard(
                            title: "Inhalte durchsuchen",
                            helpText: "Sucht gleichzeitig im gelesenen Ausgangstext, im aufbereiteten Text und in den erkannten Stellen dieser Seite."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("z. B. 01.10.1938 oder Offenau", text: $query)
                                    .textFieldStyle(.roundedBorder)

                                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Suche nach Ausgangstext, aufbereitetem Text und erkannten Stellen.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Treffer im Text: \(searchMatches.count)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(searchMatches.isEmpty ? .secondary : .primary)
                                }

                                if !searchMatches.isEmpty {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(searchMatches.enumerated()), id: \.offset) { index, match in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(match.section)
                                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.72 : 0.62))
                                            Text(match.snippet)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textSelection(.enabled)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(searchMatchFill(isPrimary: index == 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }

                        debugCard(
                            title: "Erkannte Stellen",
                            helpText: "Zeigt alle Stellen, die Inkognito auf dieser Seite erkannt hat, inklusive Quelle, Kategorie und Konfidenz."
                        ) {
                            if selectedEntry.findings.isEmpty {
                                Text("Keine Stellen erkannt.")
                                    .foregroundStyle(.secondary)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(selectedEntry.findings) { finding in
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 8) {
                                                Text(finding.source.label)
                                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(sourceColor(for: finding.source).opacity(0.12), in: Capsule())
                                                    .foregroundStyle(sourceColor(for: finding.source))
                                                Text(finding.category)
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            Text(finding.text)
                                                .font(.system(size: 12))
                                                .textSelection(.enabled)
                                            Text("Konfidenz \(Int(finding.confidence * 100))% · Zeichen \(finding.start)-\(finding.end)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.72 : 0.62))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(debugItemFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(debugItemBorderColor, lineWidth: 0.8)
                                        )
                                    }
                                }
                            }
                        }

                        if !selectedEntry.diagnostics.isEmpty {
                            debugCard(
                                title: "Eigene Regeln im Kontext",
                                helpText: "Zeigt, welche deiner eigenen Regeln hier mitgewirkt haben oder warum Einträge berücksichtigt oder verworfen wurden."
                            ) {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(selectedEntry.diagnostics.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(debugItemFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(debugItemBorderColor, lineWidth: 0.8)
                                            )
                                    }
                                }
                            }
                        }

                        if !selectedEntry.previewDiagnostics.isEmpty {
                            debugCard(
                                title: "Abgleich mit der Vorschau",
                                helpText: "Hilft nachzuvollziehen, welche Textstellen in der Vorschau markiert wurden und wie sie zugeordnet sind."
                            ) {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(selectedEntry.previewDiagnostics.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(debugItemFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(debugItemBorderColor, lineWidth: 0.8)
                                            )
                                    }
                                }
                            }
                        }

                        debugCard(
                            title: "Gelesener Ausgangstext",
                            helpText: "Das ist der Text, den Inkognito direkt aus PDF oder OCR übernommen hat."
                        ) {
                            Text(selectedEntry.rawText.isEmpty ? "Kein Text vorhanden." : selectedEntry.rawText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if selectedEntry.normalizedText != selectedEntry.rawText {
                            debugCard(
                                title: "Aufbereiteter Text",
                                helpText: "Das ist die interne, bereinigte Fassung für Erkennung und Abgleich. Layoutreste oder OCR-Artefakte können hier vereinfacht sein."
                            ) {
                                Text(selectedEntry.normalizedText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Ansicht kopieren") {
                                copyDiagnostics(selectedEntry)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(24)
                }
                .background(AmbientBackdrop())
            } else {
                ContentUnavailableView("Keine Ansicht ausgewählt", systemImage: "ladybug")
            }
        }
        .frame(minWidth: 860, idealWidth: 1040, minHeight: 620, idealHeight: 760)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Fertig") { dismiss() }
            }
        }
        .onAppear {
            selectedEntryID = entries.first?.id
        }
    }

    private var selectedEntry: DetectionDebugEntry? {
        guard let selectedEntryID else { return entries.first }
        return entries.first(where: { $0.id == selectedEntryID }) ?? entries.first
    }

    private func debugCard<Content: View>(title: String, helpText: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let helpText {
                    DebugInfoButton(text: helpText)
                }
            }
            content()
        }
        .padding(16)
        .background(debugCardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(debugCardBorderColor, lineWidth: 0.9)
        )
    }

    private var debugCardFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.16)
    }

    private var debugCardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var debugItemFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.72)
    }

    private var debugItemBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private func searchMatchFill(isPrimary: Bool) -> Color {
        if colorScheme == .dark {
            return Color.yellow.opacity(isPrimary ? 0.22 : 0.14)
        }
        return Color.yellow.opacity(isPrimary ? 0.18 : 0.10)
    }

    private var searchMatches: [(section: String, snippet: String)] {
        guard let selectedEntry else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var matches: [(String, String)] = []

        matches.append(contentsOf: snippetMatches(in: selectedEntry.rawText, section: "Gelesener Text", query: trimmedQuery))

        if selectedEntry.normalizedText != selectedEntry.rawText {
            matches.append(contentsOf: snippetMatches(in: selectedEntry.normalizedText, section: "Aufbereiteter Text", query: trimmedQuery))
        }

        for line in selectedEntry.diagnostics where line.localizedCaseInsensitiveContains(trimmedQuery) {
            matches.append(("Eigene Regeln im Kontext", line))
        }

        for finding in selectedEntry.findings {
            if finding.text.localizedCaseInsensitiveContains(trimmedQuery) || finding.category.localizedCaseInsensitiveContains(trimmedQuery) {
                matches.append((
                    "Erkannte Stellen · \(finding.source.label)",
                    "\(finding.category): \(finding.text)"
                ))
            }
        }

        return Array(matches.prefix(12))
    }

    private func snippetMatches(in text: String, section: String, query: String) -> [(section: String, snippet: String)] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        var ranges: [NSRange] = []

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            ranges.append(NSRange(location: lower, length: upper - lower))
            searchRange = range.upperBound..<text.endIndex
        }

        return ranges.prefix(6).compactMap { range in
            let start = max(0, range.location - 28)
            let end = min(nsText.length, range.location + range.length + 28)
            let snippet = nsText.substring(with: NSRange(location: start, length: end - start))
            let prefix = start > 0 ? "…" : ""
            let suffix = end < nsText.length ? "…" : ""
            return (section, prefix + snippet + suffix)
        }
    }

    private func sourceColor(for source: DetectionSource) -> Color {
        switch source {
        case .model: return .blue
        case .pattern: return .mint
        case .mixed: return .orange
        }
    }

    private func copyDiagnostics(_ entry: DetectionDebugEntry) {
        let findingsText = entry.findings.map {
            "[\($0.source.label)] \($0.category) · \($0.text) · \($0.start)-\($0.end) · \(Int($0.confidence * 100))%"
        }.joined(separator: "\n")
        let payload = [
            entry.title,
            entry.textSourceLabel,
            "",
            "Erkannte Stellen:",
            findingsText.isEmpty ? "Keine Stellen" : findingsText,
            "",
            "Eigene Regeln im Kontext:",
            entry.diagnostics.isEmpty ? "Keine Hinweise" : entry.diagnostics.joined(separator: "\n"),
            "",
            "Abgleich mit der Vorschau:",
            entry.previewDiagnostics.isEmpty ? "Keine Vorschauhinweise" : entry.previewDiagnostics.joined(separator: "\n"),
            "",
            "Gelesener Ausgangstext:",
            entry.rawText,
            "",
            "Aufbereiteter Text:",
            entry.normalizedText
        ].joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }
}

private struct ClipboardAnonymizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detector: PIIDetector

    @State private var originalText = ""
    @State private var anonymizedText = ""
    @State private var placeholders: [(placeholder: String, original: String)] = []
    @State private var replacementCount = 0
    @State private var aiResponseText = ""
    @State private var restoredText = ""
    @State private var restoreCount = 0
    @State private var unresolvedPlaceholders: [String] = []
    @State private var suspiciousPlaceholderTokens: [String] = []
    @State private var isProcessing = false
    @State private var statusMessage = "Kopiere einen Text und lade ihn hier zur anonymisierten Vorschau."
    @State private var restoreStatusMessage = "Lade danach die KI-Antwort, um die Platzhalter wieder zurückzuführen."

    private var statusTone: ClipboardStatusTone {
        if statusMessage.contains("fehlgeschlagen") {
            return .warning
        }
        if originalText.isEmpty {
            return .info
        }
        return .success
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zwischenablage anonymisieren")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Kopierten Text lokal anonymisieren, prüfen und später wieder zurückführen.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Button("Fertig") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }

                HStack(spacing: 12) {
                    Button("Aus Zwischenablage laden") {
                        Task { await refreshFromClipboard() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button("Anonymisierte Version kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(anonymizedText, forType: .string)
                        statusMessage = "Die anonymisierte Version liegt jetzt in der Zwischenablage."
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(anonymizedText.isEmpty)

                    Spacer(minLength: 0)

                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                statusBanner(message: statusMessage, tone: statusTone)

                HStack(alignment: .top, spacing: 20) {
                    comparisonCard(title: "Original", minHeight: 360) {
                        if originalText.isEmpty {
                            clipboardEmptyState(
                                title: "Noch nichts geladen",
                                message: "Lade einen kopierten Text aus der Zwischenablage, um hier die Originalfassung zu sehen.",
                                symbol: "doc.text"
                            )
                        } else {
                            ScrollView {
                                Text(originalText)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    comparisonCard(title: "Anonymisiert", minHeight: 360) {
                        if anonymizedText.isEmpty {
                            clipboardEmptyState(
                                title: "Noch keine Vorschau",
                                message: "Sobald ein Text anonymisiert wurde, erscheint hier die geschützte Version mit Platzhaltern.",
                                symbol: "lock.doc"
                            )
                        } else {
                            ScrollView {
                                Text(anonymizedText)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                comparisonCard(title: "Platzhalter", minHeight: 220) {
                    if placeholders.isEmpty {
                        clipboardEmptyState(
                            title: "Noch keine Platzhalter",
                            message: "Nach der Anonymisierung siehst du hier, welche Werte ersetzt und später wieder zurückgeführt werden können.",
                            symbol: "tag"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(placeholders, id: \.placeholder) { entry in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(entry.placeholder)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.blue)
                                        Text(entry.original)
                                            .font(.system(size: 12))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(10)
                                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Antwort zurückführen")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("Nutze die zuletzt erzeugten Platzhalter, um den von der KI überarbeiteten Text wieder zu personalisieren.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if let session = detector.lastClipboardSession {
                            Text("Mapping von \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Antwort aus Zwischenablage laden") {
                            loadResponseFromClipboard()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)

                        Button("Zurückgeführten Text kopieren") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(restoredText, forType: .string)
                            restoreStatusMessage = "Die personalisierte Antwort liegt jetzt in der Zwischenablage."
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(restoredText.isEmpty)
                    }

                    Text(restoreStatusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 20) {
                        comparisonCard(title: "KI-Antwort mit Platzhaltern", minHeight: 320) {
                            TextEditor(text: $aiResponseText)
                                .font(.system(size: 12.5, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onChange(of: aiResponseText) { _, newValue in
                                    restorePreview(from: newValue)
                                }
                        }

                        comparisonCard(title: "Zurückgeführt", minHeight: 320) {
                            if restoredText.isEmpty {
                                clipboardEmptyState(
                                    title: "Noch keine Rückführung",
                                    message: "Lade eine KI-Antwort mit Platzhaltern, um hier die personalisierte Vorschau zu sehen.",
                                    symbol: "arrow.uturn.backward.circle"
                                )
                            } else {
                                ScrollView {
                                    Text(restoredText)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    comparisonCard(title: "Rückführungsstatus", minHeight: 120) {
                        VStack(alignment: .leading, spacing: 10) {
                            if detector.lastClipboardSession == nil {
                                clipboardEmptyState(
                                    title: "Noch kein Mapping",
                                    message: "Starte oben zuerst eine Anonymisierung. Danach kann Inkognito Platzhalter wieder zuverlässig zurückführen.",
                                    symbol: "link.badge.plus"
                                )
                            } else {
                                Text("Ersetzte Platzhalter: \(restoreCount)")
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            if !unresolvedPlaceholders.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Noch unverändert im Antworttext:")
                                        .font(.system(size: 12, weight: .semibold))
                                    ForEach(unresolvedPlaceholders, id: \.self) { placeholder in
                                        Text(placeholder)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.orange.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }

                            if !suspiciousPlaceholderTokens.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Verdächtige Platzhalter-Varianten erkannt:")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Diese Tokens sehen nach veränderten Platzhaltern aus und sollten geprüft werden.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    ForEach(suspiciousPlaceholderTokens, id: \.self) { token in
                                        Text(token)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.red.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 960, idealWidth: 1120, minHeight: 860, idealHeight: 940)
        .background(AmbientBackdrop())
        .task {
            hydrateFromLastSession()
            await refreshFromClipboard()
        }
    }

    private func comparisonCard<Content: View>(title: String, minHeight: CGFloat = 280, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func clipboardEmptyState(title: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StatusVisualSemantics.trust)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        )
    }

    private func refreshFromClipboard() async {
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty
        else {
            originalText = ""
            anonymizedText = ""
            placeholders = []
            replacementCount = 0
            statusMessage = "Kopiere zuerst einen Text in die Zwischenablage und lade ihn dann erneut."
            return
        }

        originalText = clipboardText
        isProcessing = true
        defer { isProcessing = false }

        switch await detector.anonymizeClipboardText(clipboardText) {
        case .failure(let error):
            anonymizedText = ""
            placeholders = []
            replacementCount = 0
            statusMessage = "Die Anonymisierung hat diesmal nicht geklappt. Prüfe bitte, ob das lokale Modell bereit ist, und versuche es dann erneut. Details: \(error.localizedDescription)"
        case .success(let result):
            hydrate(from: result)
            statusMessage = result.placeholders.isEmpty
                ? "Keine passenden Inhalte gefunden. Prüfe den Text oder versuche einen anderen Ausschnitt."
                : "Bereit: \(result.placeholders.count) Platzhalter für \(result.replacementCount) Ersetzungen."
        }
    }

    private func hydrateFromLastSession() {
        guard let session = detector.lastClipboardSession else { return }
        hydrate(from: session)
    }

    private func hydrate(from session: ClipboardAnonymizationSession) {
        originalText = session.originalText
        anonymizedText = session.anonymizedText
        placeholders = session.placeholders
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        replacementCount = session.replacementCount
        restorePreview(from: aiResponseText)
    }

    private func loadResponseFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty
        else {
            restoreStatusMessage = "Kopiere zuerst die KI-Antwort in die Zwischenablage und lade sie dann erneut."
            return
        }
        aiResponseText = clipboardText
        restorePreview(from: clipboardText)
    }

    private func restorePreview(from responseText: String) {
        guard !responseText.isEmpty else {
            restoredText = ""
            restoreCount = 0
            unresolvedPlaceholders = detector.lastClipboardSession?.placeholders.keys.sorted() ?? []
            suspiciousPlaceholderTokens = []
            restoreStatusMessage = "Lade jetzt die KI-Antwort, um die Platzhalter wieder zurückzuführen."
            return
        }

        guard let result = detector.restoreText(responseText) else {
            restoredText = ""
            restoreCount = 0
            unresolvedPlaceholders = []
            suspiciousPlaceholderTokens = []
            restoreStatusMessage = "Noch kein Mapping vorhanden. Bitte anonymisiere zuerst oben einen Text."
            return
        }

        restoredText = result.restoredText
        restoreCount = result.replacementCount
        unresolvedPlaceholders = result.unresolvedPlaceholders.sorted()
        suspiciousPlaceholderTokens = result.suspiciousTokens.sorted()
        restoreStatusMessage = restoreStatusText(for: result)
    }

    private func restoreStatusText(for result: TextRestorationResult) -> String {
        if result.replacementCount == 0 {
            return "Im Antworttext wurden noch keine passenden Platzhalter gefunden."
        }
        if !result.suspiciousTokens.isEmpty {
            return "Zurückgeführt: \(result.replacementCount) Platzhalter. Bitte prüfe die verdächtigen Rest-Tokens."
        }
        if !result.unresolvedPlaceholders.isEmpty {
            return "Zurückgeführt: \(result.replacementCount) Platzhalter. Einige erwartete Tokens fehlen noch."
        }
        return "Zurückgeführt: \(result.replacementCount) Platzhalter."
    }

    private func statusBanner(message: String, tone: ClipboardStatusTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.tint)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum ClipboardStatusTone {
    case info
    case success
    case warning

    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        }
    }

    var fill: Color {
        switch self {
        case .info: .blue.opacity(0.08)
        case .success: .green.opacity(0.08)
        case .warning: .orange.opacity(0.10)
        }
    }
}

private struct CustomPatternsSheet: View {
    private enum Field: Hashable {
        case label
        case line(Int)
    }

    private enum ImportMode: String, CaseIterable, Identifiable {
        case append
        case replace

        var id: String { rawValue }

        var title: String {
            switch self {
            case .append: "Ergänzen"
            case .replace: "Ersetzen"
            }
        }
    }

    private enum RuleCategoryOption: String, CaseIterable, Identifiable {
        case customIdentifier = "custom_identifier"
        case privatePerson = "private_person"
        case privateAddress = "private_address"
        case accountNumber = "account_number"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .customIdentifier: "Eigener Begriff"
            case .privatePerson: "Person"
            case .privateAddress: "Adresse"
            case .accountNumber: "Kennung"
            }
        }

        var helpText: String {
            switch self {
            case .customIdentifier:
                "Für freie Begriffe, Namen oder Blöcke, die Inkognito zusätzlich erkennen soll."
            case .privatePerson:
                "Wenn der Eintrag klar eine Person beschreibt."
            case .privateAddress:
                "Wenn der Eintrag vor allem als Adresse behandelt werden soll."
            case .accountNumber:
                "Für Konten, Vertragsnummern, IDs oder ähnliche Kennungen."
            }
        }
    }

    private enum RuleCategorySelection: String, CaseIterable, Identifiable {
        case automatic
        case customIdentifier = "custom_identifier"
        case privatePerson = "private_person"
        case privateAddress = "private_address"
        case accountNumber = "account_number"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Automatisch"
            case .customIdentifier: "Eigener Begriff"
            case .privatePerson: "Person"
            case .privateAddress: "Adresse"
            case .accountNumber: "Kennung"
            }
        }

        var resolvedCategory: String? {
            switch self {
            case .automatic: nil
            case .customIdentifier,
                 .privatePerson,
                 .privateAddress,
                 .accountNumber:
                rawValue
            }
        }
    }

    private enum MaintenanceAction: String, Identifiable {
        case migrate
        case cleanup
        case deduplicate

        var id: String { rawValue }
    }

    private enum RuleListFilter: String, CaseIterable, Identifiable {
        case all
        case address
        case person
        case account
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "Alle"
            case .address: "Adresse"
            case .person: "Person"
            case .account: "Kennung"
            case .custom: "Begriff"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: CustomPatternStore
    @State private var label = ""
    @State private var valueLines = ["", "", ""]
    @State private var selectedCategory: RuleCategorySelection = .automatic
    @State private var selectedPatternID: UUID?
    @State private var selectedGroupPatternIDs: [UUID] = []
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importExportMessage: String?
    @State private var importMode: ImportMode = .append
    @State private var showRuleLogicInfo = false
    @State private var pendingMaintenanceAction: MaintenanceAction?
    @State private var expandedGroupIDs: Set<String> = []
    @State private var rulesFilter: RuleListFilter = .all
    @FocusState private var focusedField: Field?

    var body: some View {
        GeometryReader { proxy in
            let useSplitLayout = proxy.size.width >= 920

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerBar
                    importModeBar

                    if useSplitLayout {
                        HStack(alignment: .top, spacing: 22) {
                            activeRulesColumn
                                .frame(width: min(max(proxy.size.width * 0.34, 320), 400), alignment: .topLeading)
                            composerColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        activeRulesColumn
                        composerColumn
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .frame(minWidth: 720, idealWidth: 940, maxWidth: 1280, minHeight: 640, idealHeight: 760, maxHeight: 1100, alignment: .topLeading)
        .background(AmbientBackdrop())
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .fileExporter(
            isPresented: $isExporting,
            document: CustomPatternsTransferDocument(patterns: store.exportPatterns()),
            contentType: .json,
            defaultFilename: "Inkognito-Regeln",
            onCompletion: handleExport
        )
        .alert(item: $pendingMaintenanceAction) { action in
            switch action {
            case .migrate:
                return Alert(
                    title: Text("Bestehende Regeln ergänzen?"),
                    message: Text(migrateConfirmationMessage),
                    primaryButton: .default(Text("Ausführen"), action: migratePatterns),
                    secondaryButton: .cancel(Text("Abbrechen"))
                )
            case .cleanup:
                return Alert(
                    title: Text("Unklare Regeln entfernen?"),
                    message: Text(cleanupConfirmationMessage),
                    primaryButton: .destructive(Text("Entfernen"), action: cleanupWeakPatterns),
                    secondaryButton: .cancel(Text("Abbrechen"))
                )
            case .deduplicate:
                return Alert(
                    title: Text("Doppelte Regeln löschen?"),
                    message: Text(deduplicateConfirmationMessage),
                    primaryButton: .destructive(Text("Entfernen"), action: deduplicatePatterns),
                    secondaryButton: .cancel(Text("Abbrechen"))
                )
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Eigene Regeln")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Lege eigene Begriffe, Personen oder Adressbausteine Zeile für Zeile an und prüfe direkt, welche Regeln Inkognito daraus ableitet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Menu {
                Button("Regeln importieren") {
                    isImporting = true
                }
                Button("Regeln exportieren") {
                    isExporting = true
                }
            } label: {
                Label("Import & Export", systemImage: "arrow.up.arrow.down.circle")
            }
            .menuStyle(.button)
            .controlSize(.large)

            Button("Fertig") { dismiss() }
                .controlSize(.large)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 4)
    }

    private var composerColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard(title: selectedPatternID == nil ? "Neue Regel" : "Regel bearbeiten", subtitle: "Lege pro Zeile einen Baustein an. Inkognito zeigt dir danach direkt, welche Regeln daraus entstehen.") {
                VStack(alignment: .leading, spacing: 18) {
                    fieldGroup(title: "Name der Regel", footnote: "Dieser Name erscheint später in der Liste deiner eigenen Regeln.") {
                        TextField("z. B. Familie Mustermann oder Lieferadresse", text: $label)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(fieldFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(fieldTextColor)
                            .overlay(fieldBorder(isFocused: focusedField == .label, cornerRadius: 14))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 10, y: 4)
                            .focused($focusedField, equals: .label)
                    }

                    fieldGroup(title: "Bausteine eingeben", trailingText: "Eine Zeile pro Baustein", footnote: "Geeignet für einzelne Werte ebenso wie für vollständige Adressblöcke.") {
                        HStack(spacing: 10) {
                            Text("Name, Straße, PLZ/Ort oder weitere Bausteine jeweils in eine eigene Zeile setzen.")
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.76))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button {
                                showRuleLogicInfo = true
                            } label: {
                                Label("Wie wird das bewertet?", systemImage: "info.circle")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .popover(isPresented: $showRuleLogicInfo, arrowEdge: .top) {
                                ruleExplanationCard
                                    .frame(width: 360)
                                    .padding(16)
                            }
                        }

                        rulesLineEditor
                    }

                    fieldGroup(title: "Einordnung", footnote: categoryFootnote) {
                        Picker("Einordnung", selection: $selectedCategory) {
                            ForEach(RuleCategorySelection.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            if !previewPatterns.isEmpty {
                sectionCard(title: "Vorschau vor dem Speichern", subtitle: "Diese Regeln werden aus deinen Eingaben neu angelegt:") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            previewSummary

                            ForEach(previewPatterns) { pattern in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(previewBadgeText(for: pattern))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(previewBadgeColor(for: pattern))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(previewBadgeColor(for: pattern).opacity(0.12), in: Capsule())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pattern.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(pattern.value)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(secondaryCardFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(secondaryCardBorderColor, lineWidth: 0.8)
                                )
                            }
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 240)
                }
            }

            HStack(spacing: 12) {
                Button(selectedPatternID == nil ? "Regel hinzufügen" : "Regel aktualisieren", action: savePattern)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || composedValue.isEmpty)

                if selectedPatternID != nil {
                    Button("Neue Regel beginnen", action: resetEditor)
                        .controlSize(.large)
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var activeRulesColumn: some View {
        sectionCard(title: "Deine Regeln", subtitle: "\(patternGroups.count) Regeln mit \(store.patterns.count) abgeleiteten Einträgen") {
            HStack(spacing: 10) {
                Button("Regeln ergänzen") {
                    pendingMaintenanceAction = .migrate
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button("Unklare Regeln entfernen") {
                    pendingMaintenanceAction = .cleanup
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button("Doppelte Regeln löschen") {
                    pendingMaintenanceAction = .deduplicate
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Regeln ergänzen erstellt zusätzliche Teil- oder Blockregeln aus bestehenden Einträgen.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.76 : 0.64))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Unklare Regeln entfernen löscht voraussichtlich wenig hilfreiche Einträge. Doppelte Regeln löschen bereinigt identische Regeln.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.76 : 0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let importExportMessage {
                compactHintCard(importExportMessage)
            }

            if !store.patterns.isEmpty {
                fieldGroup(title: "Filter", footnote: "Zeigt nur passende Regelgruppen in der Liste.") {
                    Picker("Filter", selection: $rulesFilter) {
                        ForEach(RuleListFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if store.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch keine eigenen Regeln angelegt.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.82))
                    Text("Importiere eine Regeldatei oder lege rechts deine erste Regel an.")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.68))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                if filteredPatternGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keine Regeln für diesen Filter.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.82))
                        Text("Wähle einen anderen Filter oder lege eine neue Regel in dieser Einordnung an.")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.68))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(filteredPatternGroups) { group in
                                ruleGroupCard(group)
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }
            }
        }
    }

    private var importModeBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Beim Import")
                    .font(.system(size: 13, weight: .semibold))
                Text("Steuert nur den nächsten Import und verändert das Anlegen neuer Regeln nicht.")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.80 : 0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker("Importmodus", selection: $importMode) {
                ForEach(ImportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(hintCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(hintCardBorderColor, lineWidth: 0.8)
                )
        )
    }

    private func savePattern() {
        let category = effectiveCategory.rawValue
        if !selectedGroupPatternIDs.isEmpty {
            store.replaceGroup(ids: selectedGroupPatternIDs, label: label, value: composedValue, category: category)
        } else if let selectedPatternID {
            store.update(id: selectedPatternID, label: label, value: composedValue, category: category)
        } else {
            store.add(label: label, value: composedValue, category: category)
        }
        resetEditor()
    }

    private var previewPatterns: [CustomPattern] {
        store.previewPatterns(label: label, value: composedValue, category: effectiveCategory.rawValue)
    }

    private var patternGroups: [CustomPatternStore.PatternGroup] {
        store.groupedPatterns()
    }

    private var filteredPatternGroups: [CustomPatternStore.PatternGroup] {
        patternGroups.filter { group in
            switch rulesFilter {
            case .all:
                return true
            case .address:
                return resolvedFilterCategory(for: group) == .privateAddress
            case .person:
                return resolvedFilterCategory(for: group) == .privatePerson
            case .account:
                return resolvedFilterCategory(for: group) == .accountNumber
            case .custom:
                return resolvedFilterCategory(for: group) == .customIdentifier
            }
        }
    }

    private var composedValue: String {
        normalizedLines.joined(separator: "\n")
    }

    private var normalizedLines: [String] {
        valueLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var previewSummary: some View {
        HStack(spacing: 8) {
            summaryChip(title: "Original", count: previewPatterns.filter { !$0.label.contains("Teil") && !$0.label.contains("Block") }.count, color: .blue)
            summaryChip(title: "Teilregeln", count: previewPatterns.filter { $0.label.contains("Teil") }.count, color: .teal)
            summaryChip(title: "Blockregeln", count: previewPatterns.filter { $0.label.contains("Block") }.count, color: .indigo)
        }
    }

    private var effectiveCategory: RuleCategoryOption {
        if let explicit = selectedCategory.resolvedCategory.flatMap({ RuleCategoryOption(rawValue: $0) }) {
            return explicit
        }
        return inferredCategory
    }

    private var inferredCategory: RuleCategoryOption {
        let joined = normalizedLines.joined(separator: " ")
        if looksLikeAddressBlock(normalizedLines) {
            return .privateAddress
        }
        if looksLikeIdentifier(joined) {
            return .accountNumber
        }
        if looksLikePersonName(joined) {
            return .privatePerson
        }
        return .customIdentifier
    }

    private var categoryFootnote: String {
        if selectedCategory == .automatic {
            if effectiveCategory == .customIdentifier {
                return "Inkognito ordnet die Eingabe derzeit neutral als „Eigener Begriff“ ein. Wenn du schon weißt, dass es eher eine Person, Adresse oder Kennung ist, kannst du das hier festlegen."
            }
            return "Inkognito ordnet die Eingabe derzeit als „\(effectiveCategory.title)“ ein. Du kannst die Einordnung bei Bedarf überschreiben."
        }
        return effectiveCategory.helpText
    }

    private var migrateConfirmationMessage: String {
        let addedCount = store.previewLegacyMigrationAddedCount()
        if addedCount > 0 {
            return "Inkognito ergänzt voraussichtlich \(addedCount) zusätzliche Teil- oder Blockregeln aus deinen vorhandenen Regeln."
        }
        return "Inkognito prüft deine vorhandenen Regeln und ergänzt aktuell keine weiteren Ableitungen."
    }

    private var cleanupConfirmationMessage: String {
        let removedCount = store.previewWeakPatternRemovalCount()
        if removedCount > 0 {
            return "Inkognito hat \(removedCount) voraussichtlich wenig hilfreiche oder unklare Regeln gefunden. Möchtest du sie entfernen?"
        }
        return "Aktuell wurden keine unklaren Regeln gefunden."
    }

    private var deduplicateConfirmationMessage: String {
        let removedCount = store.previewDeduplicateRemovalCount()
        if removedCount > 0 {
            return "Inkognito hat \(removedCount) doppelte Regeln gefunden. Möchtest du diese Duplikate entfernen?"
        }
        return "Aktuell wurden keine doppelten Regeln gefunden."
    }

    private func sectionCard<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(sectionCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(sectionCardBorderColor, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.035), radius: 16, y: 6)
    }

    private func compactHintCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(hintCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(hintCardBorderColor, lineWidth: 0.8)
                )
        )
    }

    private func fieldGroup<Content: View>(
        title: String,
        trailingText: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer(minLength: 0)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.78 : 0.62))
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.84 : 0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
    }

    private var ruleExplanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("So bewertet Inkognito deine Eingaben")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))

            VStack(alignment: .leading, spacing: 7) {
                explanationLine("Der komplette Block wird als Originalregel gespeichert.")
                explanationLine("Zusätzlich entstehen Teilregeln pro Zeile oder pro Komma-getrenntem Baustein.")
                explanationLine("Nur benachbarte Bausteine werden zu Blockregeln kombiniert, zum Beispiel Name + Straße oder Straße + PLZ/Ort.")
                explanationLine("Es gibt keine automatische Umstellung wie „Mustermann Max“.")
            }
        }
        .padding(14)
        .background(secondaryCardFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(secondaryCardBorderColor, lineWidth: 0.8)
        )
    }

    private func ruleGroupCard(_ group: CustomPatternStore.PatternGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        let isSelected = selectedPatternID == group.editorPattern.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    toggleGroup(group.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    selectGroup(group)
                    expandedGroupIDs.insert(group.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Regelname")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(group.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            groupMetaChip("\(group.componentCount) Bausteine")
                            groupMetaChip(displayCategoryTitle(group.category, sampleValue: group.editorPattern.value))
                            if !group.derivedPatterns.isEmpty {
                                groupMetaChip("\(group.derivedPatterns.count) Ableitungen")
                            }
                        }

                        Text(group.editorPattern.value)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(isExpanded ? nil : 3)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button("Löschen") {
                    removeGroup(group)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .overlay(dividerColor)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    if let original = group.original {
                        derivedPatternRow(pattern: original, badgeTitle: "Original")
                    }
                    ForEach(group.derivedPatterns) { pattern in
                        derivedPatternRow(
                            pattern: pattern,
                            badgeTitle: pattern.label.contains("Block") ? "Block" : "Teil"
                        )
                    }
                }
                .padding(12)
            }
        }
        .background(
            (isSelected ? selectedRuleCardFillColor : ruleCardFillColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? selectedRuleCardBorderColor : ruleCardBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 10, y: 3)
    }

    private func derivedPatternRow(pattern: CustomPattern, badgeTitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badgeTitle)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.88 : 0.82))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chipFillColor, in: Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))
                Text(pattern.value)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.82))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    private var rulesLineEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(Array(valueLines.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(chipFillColor, in: Circle())

                        TextField(linePlaceholder(at: index), text: lineBinding(at: index))
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(fieldFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(fieldTextColor)
                            .overlay(fieldBorder(isFocused: focusedField == .line(index), cornerRadius: 14))
                            .focused($focusedField, equals: .line(index))

                        Button {
                            removeLine(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(valueLines.count > 1 ? Color.red.opacity(0.9) : .secondary.opacity(0.4))
                        .disabled(valueLines.count == 1)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Zeile hinzufügen", action: addLine)
                    .buttonStyle(.glass)
                    .controlSize(.small)

                Button("Beispiel einsetzen", action: insertExampleBlock)
                    .buttonStyle(.glass)
                    .controlSize(.small)

                Button("Eingaben leeren", action: clearLines)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(normalizedLines.isEmpty)
            }
        }
    }

    private func explanationLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.9))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupMetaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.88 : 0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipFillColor, in: Capsule())
    }

    private func summaryChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 7, height: 7)

            Text("\(title) \(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.88 : 0.82))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipFillColor.opacity(colorScheme == .dark ? 0.95 : 0.82), in: Capsule())
    }

    private func previewBadgeText(for pattern: CustomPattern) -> String {
        if pattern.label.contains("Teil") {
            return "Teilregel"
        }
        if pattern.label.contains("Block") {
            return "Blockregel"
        }
        return "Originalregel"
    }

    private func previewBadgeColor(for pattern: CustomPattern) -> Color {
        if pattern.label.contains("Teil") {
            return .teal
        }
        if pattern.label.contains("Block") {
            return .indigo
        }
        return .blue
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let importedPatterns = try JSONDecoder().decode([CustomPattern].self, from: data)
            let importedCount = store.importPatterns(importedPatterns, replaceExisting: importMode == .replace)
            importExportMessage = importedCount > 0
                ? importMode == .replace
                    ? "\(importedCount) Regeln übernommen und Bestand ersetzt."
                    : "\(importedCount) Regeln importiert."
                : importMode == .replace
                    ? "Keine gültigen Regeln zum Ersetzen gefunden."
                    : "Keine neuen Regeln importiert."
        } catch {
            importExportMessage = "Import fehlgeschlagen."
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            importExportMessage = "Regeln exportiert."
        case .failure:
            importExportMessage = "Export abgebrochen oder fehlgeschlagen."
        }
    }

    private func deduplicatePatterns() {
        let removedCount = store.deduplicatePatterns()
        importExportMessage = removedCount > 0
            ? "\(removedCount) doppelte Regeln entfernt."
            : "Keine doppelten Regeln gefunden."
    }

    private func cleanupWeakPatterns() {
        let removedCount = store.cleanupWeakPatterns()
        importExportMessage = removedCount > 0
            ? "\(removedCount) unklare Regeln entfernt."
            : "Keine unklaren Regeln gefunden."
    }

    private func migratePatterns() {
        let addedCount = store.migrateLegacyPatterns()
        importExportMessage = addedCount > 0
            ? "\(addedCount) zusätzliche Ableitungen ergänzt."
            : "Keine zusätzlichen Ableitungen nötig."
    }

    private func lineBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard valueLines.indices.contains(index) else { return "" }
                return valueLines[index]
            },
            set: { newValue in
                guard valueLines.indices.contains(index) else { return }
                valueLines[index] = newValue
            }
        )
    }

    private func linePlaceholder(at index: Int) -> String {
        switch index {
        case 0: "Name oder Firma"
        case 1: "Straße und Hausnummer"
        case 2: "PLZ und Ort"
        case 3: "Land oder Zusatz"
        default: "Weiterer Baustein"
        }
    }

    private func addLine() {
        valueLines.append("")
    }

    private func removeLine(at index: Int) {
        guard valueLines.count > 1, valueLines.indices.contains(index) else { return }
        valueLines.remove(at: index)
    }

    private func insertExampleBlock() {
        valueLines = [
            "Max Mustermann",
            "Friedenstraße 25",
            "74223 Sommerfeld",
            "Deutschland"
        ]
    }

    private func clearLines() {
        valueLines = ["", "", ""]
    }

    private func resetEditor() {
        selectedPatternID = nil
        selectedGroupPatternIDs = []
        label = ""
        valueLines = ["", "", ""]
        selectedCategory = .automatic
    }

    private func selectPattern(_ pattern: CustomPattern) {
        selectedPatternID = pattern.id
        selectedGroupPatternIDs = [pattern.id]
        label = pattern.label
        valueLines = pattern.value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if valueLines.isEmpty {
            valueLines = [pattern.value]
        }
        selectedCategory = selectionForEditor(category: pattern.category, value: pattern.value)
    }

    private func selectGroup(_ group: CustomPatternStore.PatternGroup) {
        let pattern = group.editorPattern
        selectedPatternID = pattern.id
        selectedGroupPatternIDs = group.patterns.map(\.id)
        label = group.title
        valueLines = pattern.value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if valueLines.isEmpty {
            valueLines = [pattern.value]
        }
        selectedCategory = selectionForEditor(category: group.category, value: pattern.value)
    }

    private func removeGroup(_ group: CustomPatternStore.PatternGroup) {
        if group.patterns.contains(where: { $0.id == selectedPatternID }) {
            resetEditor()
        }
        store.remove(ids: group.patterns.map(\.id))
        expandedGroupIDs.remove(group.id)
    }

    private func toggleGroup(_ id: String) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    private func looksLikeAddressBlock(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: " ")
        let hasStreet = joined.localizedCaseInsensitiveContains("straße")
            || joined.localizedCaseInsensitiveContains("str.")
            || joined.localizedCaseInsensitiveContains("weg")
            || joined.localizedCaseInsensitiveContains("allee")
            || joined.localizedCaseInsensitiveContains("platz")
            || joined.localizedCaseInsensitiveContains("ring")
            || joined.localizedCaseInsensitiveContains("gasse")
        let hasPostalCode = lines.contains { $0.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil }
        return hasStreet || (hasPostalCode && lines.count >= 2)
    }

    private func looksLikePersonName(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count == 2 else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
    }

    private func looksLikeIdentifier(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber).count
        let letters = text.filter(\.isLetter).count
        return digits >= 4 && (letters == 0 || text.contains("-") || text.contains("/"))
    }

    private func selectionForEditor(category: String, value: String) -> RuleCategorySelection {
        if let explicit = RuleCategorySelection(rawValue: category), explicit != .customIdentifier {
            return explicit
        }

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if looksLikeAddressBlock(lines) {
            return .privateAddress
        }
        if looksLikeIdentifier(value) {
            return .accountNumber
        }
        if looksLikePersonName(value) {
            return .privatePerson
        }
        return RuleCategorySelection(rawValue: category) ?? .automatic
    }

    private func displayCategoryTitle(_ rawValue: String, sampleValue: String? = nil) -> String {
        if rawValue == RuleCategoryOption.customIdentifier.rawValue, let sampleValue {
            let lines = sampleValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if looksLikeAddressBlock(lines) {
                return RuleCategoryOption.privateAddress.title
            }
            if looksLikeIdentifier(sampleValue) {
                return RuleCategoryOption.accountNumber.title
            }
            if looksLikePersonName(sampleValue) {
                return RuleCategoryOption.privatePerson.title
            }
        }
        return RuleCategoryOption(rawValue: rawValue)?.title ?? rawValue
    }

    private func resolvedFilterCategory(for group: CustomPatternStore.PatternGroup) -> RuleCategoryOption {
        let sampleValue = group.editorPattern.value
        if group.category == RuleCategoryOption.customIdentifier.rawValue {
            let lines = sampleValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if looksLikeAddressBlock(lines) {
                return .privateAddress
            }
            if looksLikeIdentifier(sampleValue) {
                return .accountNumber
            }
            if looksLikePersonName(sampleValue) {
                return .privatePerson
            }
        }
        return RuleCategoryOption(rawValue: group.category) ?? .customIdentifier
    }

    private var sectionCardFillColor: Color {
        colorScheme == .dark
            ? SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme)
            : Color.white.opacity(0.78)
    }

    private var sectionCardBorderColor: Color {
        colorScheme == .dark
            ? SurfaceVisualSemantics.elevatedPanelBorder(colorScheme: colorScheme)
            : Color.black.opacity(0.08)
    }

    private var hintCardFillColor: Color {
        SurfaceVisualSemantics.secondaryPanelFill(colorScheme: colorScheme)
    }

    private var hintCardBorderColor: Color {
        SurfaceVisualSemantics.secondaryPanelBorder(colorScheme: colorScheme)
    }

    private var secondaryCardFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.72)
    }

    private var secondaryCardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var ruleCardFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.92)
    }

    private var ruleCardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var selectedRuleCardFillColor: Color {
        SurfaceVisualSemantics.selectionAccentFill(colorScheme: colorScheme)
    }

    private var selectedRuleCardBorderColor: Color {
        SurfaceVisualSemantics.selectionAccentBorder(colorScheme: colorScheme)
    }

    private var chipFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.82)
    }

    private var fieldFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.white.opacity(0.94)
    }

    private var fieldTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.84)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private func fieldBorder(isFocused: Bool, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                isFocused
                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.72 : 0.45)
                    : (colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)),
                lineWidth: isFocused ? 2 : 1
            )
    }
}

private struct CustomPatternsTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var patterns: [CustomPattern]

    init(patterns: [CustomPattern]) {
        self.patterns = patterns
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        patterns = try JSONDecoder().decode([CustomPattern].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(patterns)
        return .init(regularFileWithContents: data)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}

private struct WorkflowStepStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    enum Step: Int {
        case detect = 1
        case review = 2
        case save = 3
    }

    let currentStep: Step

    var body: some View {
        HStack(spacing: 10) {
            stepBadge(number: 1, title: "Erkennen", isActive: currentStep == .detect, isCompleted: currentStep.rawValue > 1)
            connector
            stepBadge(number: 2, title: "Freigeben", isActive: currentStep == .review, isCompleted: currentStep.rawValue > 2)
            connector
            stepBadge(number: 3, title: "Exportieren", isActive: currentStep == .save, isCompleted: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(SurfaceVisualSemantics.elevatedPanelBorder(colorScheme: colorScheme), lineWidth: 0.6)
        )
    }

    private func stepBadge(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : (isCompleted ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .frame(width: 22, height: 22)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? Color.white : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private var connector: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 18, height: 2)
    }
}

private struct PDFPageNavigationBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let currentPageIndex: Int
    let pageCount: Int
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoPrevious)

            Text("Seite \(currentPageIndex + 1) von \(pageCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 96)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoNext)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(SurfaceVisualSemantics.elevatedPanelBorder(colorScheme: colorScheme), lineWidth: 0.6)
        )
    }
}

private struct ReviewSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    let findings: [ReviewFinding]
    let pendingCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let hasProtectedContent: Bool
    let selectedFindingID: UUID?
    let undoNotice: ReviewUndoNotice?
    let exportReport: ExportValidationReport?
    let onAcceptAll: () -> Void
    let onSave: () -> Void
    let onDismissUndoNotice: () -> Void
    let onUndoLastDecision: () -> Void
    let onSelect: (UUID) -> Void
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onReopen: (UUID) -> Void
    @State private var showOnlyPending = true
    @State private var confirmAcceptAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Schutz prüfen")
                            .font(.system(size: 15, weight: .semibold))
                        Text(headerText)
                            .font(.system(size: 12))
                            .foregroundStyle(pendingCount > 0 ? .orange : .secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    Spacer(minLength: 0)

                    if pendingCount > 0 {
                        Button("Alle freigeben") {
                            confirmAcceptAll = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }

                summaryRow

                if !findings.isEmpty {
                    categoryLegend
                }

                if let undoNotice {
                    undoBanner(undoNotice)
                }

                if pendingCount == 0, !findings.isEmpty, hasProtectedContent {
                    successBanner
                }

                if pendingCount == 0, !findings.isEmpty, !hasProtectedContent {
                    noProtectedContentBanner
                }

                if let exportReport {
                    exportTrustBanner(report: exportReport)
                }

                Toggle("Nur offene Stellen", isOn: $showOnlyPending)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(pendingCount == 0)

                if isShowingFocusedNonPendingFinding {
                    Text("Der fokussierte Treffer bleibt sichtbar, damit du ihn direkt wieder öffnen kannst.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if findings.isEmpty {
                emptyInspectorState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredFindings) { finding in
                                ReviewFindingRow(
                                    finding: finding,
                                    isSelected: selectedFindingID == finding.id,
                                    onSelect: { onSelect(finding.id) },
                                    onAccept: { onAccept(finding.id) },
                                    onReject: { onReject(finding.id) },
                                    onReopen: { onReopen(finding.id) }
                                )
                                .id(finding.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: selectedFindingID) { _, id in
                        guard let id else { return }
                        withAnimation(.snappy(duration: 0.28)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(SurfaceVisualSemantics.elevatedPanelFill(colorScheme: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SurfaceVisualSemantics.elevatedPanelBorder(colorScheme: colorScheme), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.07), radius: 18, y: 7)
        .confirmationDialog("Alle offenen Stellen freigeben?", isPresented: $confirmAcceptAll, titleVisibility: .visible) {
            Button("Alle freigeben") {
                onAcceptAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Damit werden \(pendingCount) aktuell offene Stellen ohne Einzelprüfung freigegeben.")
        }
    }

    private var headerText: String {
        if findings.isEmpty {
            return "Nach der Erkennung erscheinen hier die vorgeschlagenen Schutzstellen zur Prüfung."
        }
        if pendingCount > 0 {
            return "\(pendingCount) Stellen warten vor dem Export noch auf deine Freigabe."
        }
        if !hasProtectedContent {
            return "Alles geprüft. Aktuell ist noch keine geschützte Stelle aktiv."
        }
        return "Alles geprüft. Du kannst jetzt geschützt exportieren."
    }

    private var filteredFindings: [ReviewFinding] {
        if showOnlyPending && pendingCount > 0 {
            return findings.filter { finding in
                finding.status == .pending || finding.id == selectedFindingID
            }
        }
        return findings
    }

    private var isShowingFocusedNonPendingFinding: Bool {
        guard showOnlyPending,
              pendingCount > 0,
              let selectedFindingID,
              let selectedFinding = findings.first(where: { $0.id == selectedFindingID }) else {
            return false
        }
        return selectedFinding.status != .pending
    }

    private var summaryRow: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8)
            ],
            spacing: 8
        ) {
            summaryBadge(title: "Erkannt", value: findings.count, tint: StatusVisualSemantics.neutral)
            summaryBadge(title: "Offen", value: pendingCount, tint: StatusVisualSemantics.attention)
            summaryBadge(title: "Bestätigt", value: acceptedCount, tint: StatusVisualSemantics.reviewComplete)
            summaryBadge(title: "Abgelehnt", value: rejectedCount, tint: StatusVisualSemantics.danger)
        }
    }

    private func summaryBadge(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(value > 0 ? tint : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(summaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(summaryBorder, lineWidth: 0.6)
        )
    }

    private var emptyInspectorState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Noch nichts zu prüfen")
                .font(.system(size: 13, weight: .semibold))

            Text("Starte `Erkennen`, damit hier die vorgeschlagenen Schutzstellen erscheinen. Danach kannst du sie freigeben oder ablehnen.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(summaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(summaryBorder, lineWidth: 0.6)
        )
    }

    private var categoryLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Farblegende")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(FindingVisualSemantics.legendItems.chunked(into: 3).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.category) { item in
                            legendChip(title: item.title, color: FindingVisualSemantics.color(for: item.category))
                        }
                    }
                }
            }
        }
    }

    private func legendChip(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.92))
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(summaryFill, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(summaryBorder, lineWidth: 0.6)
        )
    }

    private var successBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(StatusVisualSemantics.softFill(StatusVisualSemantics.reviewComplete, colorScheme: colorScheme, strong: true))
                        .frame(width: 28, height: 28)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(StatusVisualSemantics.reviewComplete)
                        .symbolEffect(.bounce, value: pendingCount)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Alles geprüft")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(StatusVisualSemantics.reviewComplete.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Text("Alle Stellen sind entschieden. Du kannst die geschützte Kopie jetzt exportieren.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Bereit zum Export")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(StatusVisualSemantics.reviewComplete.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(StatusVisualSemantics.softFill(StatusVisualSemantics.reviewComplete, colorScheme: colorScheme, strong: true), in: Capsule())

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onSave) {
                    Label {
                        Text("Geschützte Kopie exportieren")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(StatusVisualSemantics.reviewComplete)

                Text("oder ⌘S")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    StatusVisualSemantics.softFill(StatusVisualSemantics.reviewComplete, colorScheme: colorScheme, strong: true),
                    StatusVisualSemantics.softFill(StatusVisualSemantics.trust, colorScheme: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(StatusVisualSemantics.softBorder(StatusVisualSemantics.reviewComplete, colorScheme: colorScheme), lineWidth: 0.9)
        )
    }

    private var noProtectedContentBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(StatusVisualSemantics.softFill(StatusVisualSemantics.attention, colorScheme: colorScheme, strong: true))
                        .frame(width: 28, height: 28)

                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(StatusVisualSemantics.attention)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Noch keine geschützte Stelle aktiv")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(StatusVisualSemantics.attention.opacity(0.96))

                    Text("Alle Entscheidungen sind getroffen, aber aktuell ist nichts mehr geschwärzt. Lege mindestens eine Schwärzung an oder starte die Erkennung erneut, bevor du exportierst.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [
                    StatusVisualSemantics.softFill(StatusVisualSemantics.attention, colorScheme: colorScheme, strong: true),
                    StatusVisualSemantics.softFill(StatusVisualSemantics.neutral, colorScheme: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(StatusVisualSemantics.softBorder(StatusVisualSemantics.attention, colorScheme: colorScheme), lineWidth: 0.8)
        )
    }

    private func undoBanner(_ notice: ReviewUndoNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StatusVisualSemantics.attention)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(notice.detail.isEmpty ? "Die letzte Entscheidung kann direkt wieder geöffnet werden." : notice.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button("Rückgängig", action: onUndoLastDecision)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(StatusVisualSemantics.attention)

                Button(action: onDismissUndoNotice) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    StatusVisualSemantics.softFill(StatusVisualSemantics.attention, colorScheme: colorScheme, strong: true),
                    StatusVisualSemantics.softFill(StatusVisualSemantics.reviewComplete, colorScheme: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(StatusVisualSemantics.softBorder(StatusVisualSemantics.attention, colorScheme: colorScheme), lineWidth: 0.8)
        )
    }

    private func exportTrustBanner(report: ExportValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(StatusVisualSemantics.softFill(StatusVisualSemantics.trust, colorScheme: colorScheme, strong: true))
                        .frame(width: 28, height: 28)

                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(StatusVisualSemantics.trust)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Export geprüft")
                        .font(.system(size: 12.5, weight: .semibold))

                    Text(report.shortStatusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.trustChecklist, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(StatusVisualSemantics.trust)
                            .padding(.top, 2)

                        Text(item)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [
                    StatusVisualSemantics.softFill(StatusVisualSemantics.trust, colorScheme: colorScheme, strong: true),
                    StatusVisualSemantics.softFill(StatusVisualSemantics.trust, colorScheme: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(StatusVisualSemantics.softBorder(StatusVisualSemantics.trust, colorScheme: colorScheme), lineWidth: 0.8)
        )
    }

    private var summaryFill: Color {
        SurfaceVisualSemantics.secondaryPanelFill(colorScheme: colorScheme)
    }

    private var summaryBorder: Color {
        SurfaceVisualSemantics.secondaryPanelBorder(colorScheme: colorScheme)
    }
}

private struct ReviewFindingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let finding: ReviewFinding
    let isSelected: Bool
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onReopen: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(categoryColor.opacity(0.84))
                    .frame(width: 4)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onSelect) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(displayCategory)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(categoryTextColor)
                                Spacer(minLength: 0)
                                statusBadge
                            }

                            Text(finding.snippet.isEmpty ? "Ohne Textausschnitt" : finding.snippet)
                                .font(.system(size: 13))
                                .foregroundStyle(snippetColor)
                                .lineLimit(isExpanded ? 4 : 2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        HStack(spacing: 8) {
                            sourceBadge
                            confidenceBadge
                            if let pageIndex = finding.pageIndex {
                                Text("Seite \(pageIndex + 1)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(pageLabelColor)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Text(isExpanded ? "Weniger" : "Details")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(detailControlColor)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        if finding.status == .pending {
                            Button("Bestätigen", action: onAccept)
                                .buttonStyle(.borderedProminent)
                            Button("Ablehnen", action: onReject)
                                .buttonStyle(.bordered)
                        } else {
                            Button(finding.status == .accepted ? "Rückgängig" : "Wieder öffnen", action: onReopen)
                                .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.9)
        )
        .shadow(color: shadowColor, radius: 16, y: 6)
    }

    private var displayCategory: String {
        FindingVisualSemantics.displayName(for: finding.category)
    }

    private var sourceBadge: some View {
        Text(finding.source.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(StatusVisualSemantics.softFill(sourceTone, colorScheme: colorScheme, strong: true), in: Capsule())
            .foregroundStyle(sourceTone)
    }

    private var cardFill: Color {
        if isSelected {
            return SurfaceVisualSemantics.selectionAccentFill(colorScheme: colorScheme)
        }
        return SurfaceVisualSemantics.secondaryPanelFill(colorScheme: colorScheme)
    }

    private var cardBorder: Color {
        if isSelected {
            return SurfaceVisualSemantics.selectionAccentBorder(colorScheme: colorScheme)
        }
        return SurfaceVisualSemantics.secondaryPanelBorder(colorScheme: colorScheme)
    }

    private var shadowColor: Color {
        if isSelected {
            return SurfaceVisualSemantics.selectionShadow(colorScheme: colorScheme)
        }
        return colorScheme == .dark ? Color.black.opacity(0.16) : Color.black.opacity(0.055)
    }

    private var snippetColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.90) : .secondary
    }

    private var detailControlColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : .secondary
    }

    private var pageLabelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : .secondary.opacity(0.9)
    }

    private var confidenceBadge: some View {
        Text("Konf. \(confidenceText)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryColor.opacity(0.06), in: Capsule())
            .foregroundStyle(confidenceTextColor)
    }

    private var statusBadge: some View {
        Text(finding.status.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(StatusVisualSemantics.softFill(statusTone, colorScheme: colorScheme, strong: true), in: Capsule())
            .foregroundStyle(statusTone)
    }

    private var sourceTone: Color {
        StatusVisualSemantics.detectionSourceTone(for: finding.source)
    }

    private var categoryColor: Color {
        FindingVisualSemantics.color(for: finding.category)
    }

    private var categoryTextColor: Color {
        let alpha: Double = colorScheme == .dark ? 0.98 : 0.82
        return categoryColor.opacity(alpha)
    }

    private var confidenceTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : .secondary
    }

    private var statusTone: Color {
        StatusVisualSemantics.reviewStatusTone(for: finding.status)
    }

    private var confidenceText: String {
        (Double(finding.confidence) * 100)
            .formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

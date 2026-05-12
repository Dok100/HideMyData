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
                            onAcceptAll: acceptAllFindings,
                            onSelect: selectFinding,
                            onAccept: acceptFinding,
                            onReject: rejectFinding
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

    private func openPDFAndAdd() {
        guard pdfRedactor.openPDF(), let url = pdfRedactor.sourceURL else { return }
        recents.add(url: url, kind: .pdf)
        showHome = false
    }

    private func openImageAndAdd() {
        guard imageRedactor.openImage(), let url = imageRedactor.sourceURL else { return }
        recents.add(url: url, kind: .image)
        showHome = false
    }

    private func handleDrop(_ url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        if type.conforms(to: .pdf) {
            inputMode = .pdf
            if pdfRedactor.loadPDF(from: url) {
                recents.add(url: url, kind: .pdf)
                showHome = false
            }
        } else if type.conforms(to: .image) {
            inputMode = .image
            if imageRedactor.loadImage(from: url) {
                recents.add(url: url, kind: .image)
                showHome = false
            }
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
            return
        }

        switch item.kind {
        case .pdf:
            inputMode = .pdf
            if pdfRedactor.loadPDF(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .pdf)
                showHome = false
            }
        case .image:
            inputMode = .image
            if imageRedactor.loadImage(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .image)
                showHome = false
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

    private var currentWorkflowStep: WorkflowStepStrip.Step {
        if hasPendingReview {
            return .review
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
        guard !hasPendingReview else {
            saveWarningPresented = true
            return
        }
        switch inputMode {
        case .pdf: pdfRedactor.save()
        case .image: imageRedactor.save()
        }
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
    }
}

private struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [DetectionDebugEntry]
    @State private var selectedEntryID: DetectionDebugEntry.ID?
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(entries, selection: $selectedEntryID) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(entry.findings.count) Treffer · \(entry.textSourceLabel)")
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

                        debugCard(title: "Suche in der Diagnose") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("z. B. 01.10.1938 oder Offenau", text: $query)
                                    .textFieldStyle(.roundedBorder)

                                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Suche nach OCR-Text, normalisiertem Text und erkannten Treffern.")
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
                                                    .foregroundStyle(.secondary)
                                                Text(match.snippet)
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(.yellow.opacity(index == 0 ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }

                        debugCard(title: "Erkannte Treffer") {
                            if selectedEntry.findings.isEmpty {
                                Text("Keine Treffer erkannt.")
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
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                        }

                        debugCard(title: "Gelesener Text") {
                            Text(selectedEntry.rawText.isEmpty ? "Kein Text vorhanden." : selectedEntry.rawText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if selectedEntry.normalizedText != selectedEntry.rawText {
                            debugCard(title: "Normalisierter Text") {
                                Text(selectedEntry.normalizedText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Diagnose kopieren") {
                                copyDiagnostics(selectedEntry)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(24)
                }
                .background(AmbientBackdrop())
            } else {
                ContentUnavailableView("Keine Diagnose ausgewählt", systemImage: "ladybug")
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

    private func debugCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content()
        }
        .padding(16)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchMatches: [(section: String, snippet: String)] {
        guard let selectedEntry else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var matches: [(String, String)] = []

        matches.append(contentsOf: snippetMatches(in: selectedEntry.rawText, section: "Gelesener Text", query: trimmedQuery))

        if selectedEntry.normalizedText != selectedEntry.rawText {
            matches.append(contentsOf: snippetMatches(in: selectedEntry.normalizedText, section: "Normalisierter Text", query: trimmedQuery))
        }

        for finding in selectedEntry.findings {
            if finding.text.localizedCaseInsensitiveContains(trimmedQuery) || finding.category.localizedCaseInsensitiveContains(trimmedQuery) {
                matches.append((
                    "Treffer · \(finding.source.label)",
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
            "Treffer:",
            findingsText.isEmpty ? "Keine Treffer" : findingsText,
            "",
            "Gelesener Text:",
            entry.rawText,
            "",
            "Normalisierter Text:",
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
    @State private var statusMessage = "Kopiere einen Text in die Zwischenablage und prüfe hier die anonymisierte Vorschau."
    @State private var restoreStatusMessage = "Füge danach die KI-Antwort ein oder lade sie aus der Zwischenablage, um die Platzhalter wieder zurückzuführen."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zwischenablage anonymisieren")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Vorher-/Nachher-Vorschau für kopierten Text. Die Anonymisierung läuft lokal auf deinem Mac.")
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

                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 20) {
                    comparisonCard(title: "Original", minHeight: 360) {
                        ScrollView {
                            Text(originalText.isEmpty ? "Noch kein Text geladen." : originalText)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(originalText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    comparisonCard(title: "Anonymisiert", minHeight: 360) {
                        ScrollView {
                            Text(anonymizedText.isEmpty ? "Noch keine anonymisierte Vorschau vorhanden." : anonymizedText)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(anonymizedText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                comparisonCard(title: "Platzhalter", minHeight: 220) {
                    if placeholders.isEmpty {
                        Text("Noch keine Ersetzungen vorhanden.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
                            ScrollView {
                                Text(restoredText.isEmpty ? "Noch keine zurückgeführte Vorschau vorhanden." : restoredText)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(restoredText.isEmpty ? .secondary : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    comparisonCard(title: "Rückführungsstatus", minHeight: 120) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(detector.lastClipboardSession == nil
                                 ? "Noch kein Mapping vorhanden. Starte oben zuerst eine Anonymisierung."
                                 : "Ersetzte Platzhalter: \(restoreCount)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

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

    private func refreshFromClipboard() async {
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty
        else {
            originalText = ""
            anonymizedText = ""
            placeholders = []
            replacementCount = 0
            statusMessage = "Bitte kopiere zuerst einen Text in die Zwischenablage."
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
            statusMessage = "Anonymisierung fehlgeschlagen: \(error.localizedDescription)"
        case .success(let result):
            hydrate(from: result)
            statusMessage = result.placeholders.isEmpty
                ? "Es wurden keine ersetzbaren Inhalte gefunden."
                : "Ersetzungen: \(result.replacementCount), Platzhalter: \(result.placeholders.count)."
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
            restoreStatusMessage = "Bitte kopiere zuerst die KI-Antwort in die Zwischenablage."
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
            restoreStatusMessage = "Füge danach die KI-Antwort ein oder lade sie aus der Zwischenablage, um die Platzhalter wieder zurückzuführen."
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
}

private struct CustomPatternsSheet: View {
    private enum Field: Hashable {
        case label
        case value
        case category
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

    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CustomPatternStore
    @State private var label = ""
    @State private var value = ""
    @State private var category = "custom_identifier"
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importExportMessage: String?
    @State private var importMode: ImportMode = .append
    @FocusState private var focusedField: Field?

    var body: some View {
        GeometryReader { proxy in
            let useSplitLayout = proxy.size.width >= 980

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerBar

                    if useSplitLayout {
                        HStack(alignment: .top, spacing: 22) {
                            composerColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            activeRulesColumn
                                .frame(width: min(max(proxy.size.width * 0.34, 300), 380), alignment: .topLeading)
                        }
                    } else {
                        composerColumn
                        activeRulesColumn
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
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Eigene Erkennungsregeln")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Pflege eigene Trefferlisten, importiere Regeldateien und prüfe vor dem Speichern die erzeugten Bausteine.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                Label("Regel-Datei", systemImage: "arrow.up.arrow.down.circle")
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
            sectionCard(title: "Neue Regel", subtitle: "Gib Namen, IDs oder ganze Adressblöcke ein. Mehrzeilige Blöcke werden automatisch in robuste Teilregeln zerlegt.") {
                VStack(alignment: .leading, spacing: 18) {
                    fieldGroup(title: "Import beim Laden", footnote: "Steuert, ob importierte Regeln zum Bestand hinzugefügt oder komplett ersetzt werden.") {
                        Picker("Importmodus", selection: $importMode) {
                            ForEach(ImportMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    fieldGroup(title: "Bezeichnung") {
                        TextField("z. B. Firmenname oder Lieferadresse", text: $label)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.black.opacity(0.82))
                            .overlay(fieldBorder(isFocused: focusedField == .label, cornerRadius: 14))
                            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                            .focused($focusedField, equals: .label)
                    }

                    fieldGroup(title: "Adressblock oder Wert", trailingText: "Mehrzeilig empfohlen", footnote: "Ideal für Name, Straße, PLZ/Ort oder komplette Lieferadresse.") {
                        ZStack(alignment: .topLeading) {
                            addressEditorBackground

                            TextEditor(text: $value)
                                .font(.system(size: 15))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 16)
                                .padding(.top, 18)
                                .padding(.bottom, 16)
                                .frame(minHeight: 150)
                                .background(Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .foregroundStyle(.black.opacity(0.84))
                                .focused($focusedField, equals: .value)
                                .overlay(fieldBorder(isFocused: focusedField == .value, cornerRadius: 20))
                                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)

                            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Beispiel")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.white.opacity(0.7), in: Capsule())

                                    VStack(alignment: .leading, spacing: 8) {
                                        previewInputLine("Max Mustermann")
                                        previewInputLine("Friedensstr. 25")
                                        previewInputLine("74229 Oedheim")
                                        previewInputLine("Deutschland")
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                            }
                        }

                        HStack(spacing: 8) {
                            addressHintChip("Eine Zeile pro Baustein")
                            addressHintChip("z. B. Name, Straße, PLZ/Ort")
                        }
                    }

                    fieldGroup(title: "Kategorie", footnote: "Wird für die spätere Einordnung der Treffer verwendet.") {
                        TextField("z. B. customer_id", text: $category)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.black.opacity(0.82))
                            .overlay(fieldBorder(isFocused: focusedField == .category, cornerRadius: 14))
                            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                            .focused($focusedField, equals: .category)
                    }
                }
            }

            sectionCard(title: "Vorschau vor dem Speichern", subtitle: previewPatterns.isEmpty ? "Füge oben eine Regel oder einen Adressblock ein. Hier siehst du vor dem Speichern, welche Einträge neu erzeugt werden." : "Diese Regeln werden neu angelegt:") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if previewPatterns.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "text.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("Noch keine Vorschau verfügbar")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        } else {
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
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 240)
            }

            HStack(spacing: 12) {
                Button("Regel hinzufügen", action: addPattern)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let importExportMessage {
                    Text(importExportMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activeRulesColumn: some View {
        sectionCard(title: "Aktive Regeln", subtitle: "\(store.patterns.count) gespeicherte Regeln") {
            HStack(spacing: 10) {
                Button("Bestand modernisieren", action: migratePatterns)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Duplikate entfernen", action: deduplicatePatterns)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            if store.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch keine eigenen Regeln angelegt.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Importiere eine Regeldatei oder lege links deine erste Regel an.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.patterns) { pattern in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pattern.label)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(pattern.value)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text(pattern.category)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Button("Löschen") {
                                    store.remove(id: pattern.id)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private func addPattern() {
        store.add(label: label, value: value, category: category)
        label = ""
        value = ""
        if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            category = "custom_identifier"
        }
    }

    private var previewPatterns: [CustomPattern] {
        store.previewPatterns(label: label, value: value, category: category)
    }

    private func sectionCard<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            content()
        }
    }

    private func previewInputLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.black.opacity(0.28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private func previewBadgeText(for pattern: CustomPattern) -> String {
        if pattern.label.contains("Teil") {
            return "Teil"
        }
        if pattern.label.contains("Block") {
            return "Block"
        }
        return "Original"
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
            ? "\(removedCount) Duplikate entfernt."
            : "Keine Duplikate gefunden."
    }

    private func migratePatterns() {
        let addedCount = store.migrateLegacyPatterns()
        importExportMessage = addedCount > 0
            ? "Bestand modernisiert. \(addedCount) zusätzliche Regelbausteine ergänzt."
            : "Bestand geprüft und modernisiert."
    }

    private func fieldBorder(isFocused: Bool, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(isFocused ? .blue.opacity(0.45) : .white.opacity(0.5), lineWidth: isFocused ? 2 : 1)
    }

    private var addressEditorBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.96),
                        .white.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 1)
            )
    }

    private func addressHintChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.42), in: Capsule())
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

private struct WorkflowStepStrip: View {
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
            stepBadge(number: 2, title: "Prüfen", isActive: currentStep == .review, isCompleted: currentStep.rawValue > 2)
            connector
            stepBadge(number: 3, title: "Speichern", isActive: currentStep == .save, isCompleted: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.88), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.88), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
        )
    }
}

private struct ReviewSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    let findings: [ReviewFinding]
    let pendingCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let onAcceptAll: () -> Void
    let onSelect: (UUID) -> Void
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    @State private var showOnlyPending = true
    @State private var confirmAcceptAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Treffer prüfen")
                            .font(.system(size: 15, weight: .semibold))
                        Text(headerText)
                            .font(.system(size: 12))
                            .foregroundStyle(pendingCount > 0 ? .orange : .secondary)
                    }

                    Spacer(minLength: 0)

                    if pendingCount > 0 {
                        Button("Alle bestätigen") {
                            confirmAcceptAll = true
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                summaryRow

                if pendingCount == 0, !findings.isEmpty {
                    successBanner
                }

                Toggle("Nur offene Treffer", isOn: $showOnlyPending)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(pendingCount == 0)
            }

            if findings.isEmpty {
                emptyInspectorState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFindings) { finding in
                            ReviewFindingRow(
                                finding: finding,
                                onSelect: { onSelect(finding.id) },
                                onAccept: { onAccept(finding.id) },
                                onReject: { onReject(finding.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.985), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.07), radius: 18, y: 7)
        .confirmationDialog("Alle offenen Treffer bestätigen?", isPresented: $confirmAcceptAll, titleVisibility: .visible) {
            Button("Alle bestätigen") {
                onAcceptAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Damit werden alle aktuell offenen Treffer ohne Einzelprüfung freigegeben.")
        }
    }

    private var headerText: String {
        if findings.isEmpty {
            return "Nach der Erkennung erscheinen hier die gefundenen Stellen zur Prüfung."
        }
        if pendingCount > 0 {
            return "\(pendingCount) Treffer brauchen vor dem Speichern noch deine Entscheidung."
        }
        return "Alle Treffer wurden geprüft."
    }

    private var filteredFindings: [ReviewFinding] {
        if showOnlyPending && pendingCount > 0 {
            return findings.filter { $0.status == .pending }
        }
        return findings
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryBadge(title: "Erkannt", value: findings.count, tint: .secondary)
            summaryBadge(title: "Offen", value: pendingCount, tint: .orange)
            summaryBadge(title: "Bestätigt", value: acceptedCount, tint: .green)
        }
    }

    private func summaryBadge(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
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

            Text("Noch keine Prüfung aktiv")
                .font(.system(size: 13, weight: .semibold))

            Text("Starte `Erkennen`, damit hier die Treffer erscheinen. Danach kannst du sie bestätigen oder ablehnen.")
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

    private var successBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Alles geprüft. Du kannst jetzt speichern.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.green.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.18), lineWidth: 0.8)
        )
    }

    private var summaryFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.70)
    }

    private var summaryBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
}

private struct ReviewFindingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let finding: ReviewFinding
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
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
        switch finding.category.lowercased() {
        case "private_person":
            return "Person"
        case "private_phone":
            return "Telefon"
        case "private_email":
            return "E-Mail"
        case "private_date":
            return "Datum"
        case "private_address", "adresse":
            return "Adresse"
        case "adressblock":
            return "Adressblock"
        case "kontakt":
            return "Kontakt"
        case "account_number":
            return "Kontonummer"
        case "custom_identifier":
            return "Eigene Regel"
        case "secret":
            return "Vertraulich"
        default:
            return finding.category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var sourceBadge: some View {
        Text(finding.source.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(sourceColor.opacity(0.18), in: Capsule())
            .foregroundStyle(sourceColor)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.095) : Color.white.opacity(0.84)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.09)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.16) : Color.black.opacity(0.055)
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
            .background(statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var sourceColor: Color {
        switch finding.source {
        case .model: .blue
        case .pattern: .mint
        case .mixed: .orange
        }
    }

    private var categoryColor: Color {
        switch finding.category.lowercased() {
        case "private_email", "kontakt":
            return .green
        case "private_address", "adressblock", "adresse":
            return .red
        case "account_number":
            return Color(hue: 0.12, saturation: 0.72, brightness: 0.88)
        case "private_phone":
            return .teal
        case "private_person":
            return .blue
        case "private_date":
            return .purple
        default:
            return .orange
        }
    }

    private var categoryTextColor: Color {
        let alpha: Double = colorScheme == .dark ? 0.98 : 0.82
        switch finding.category.lowercased() {
        case "private_email", "kontakt":
            return .green.opacity(alpha)
        case "private_address", "adressblock", "adresse":
            return .red.opacity(alpha)
        case "account_number":
            return Color(
                hue: 0.12,
                saturation: colorScheme == .dark ? 0.48 : 0.72,
                brightness: colorScheme == .dark ? 0.96 : 0.72
            )
        case "private_phone":
            return .teal.opacity(alpha)
        case "private_person":
            return .blue.opacity(alpha)
        case "private_date":
            return .purple.opacity(alpha)
        default:
            return colorScheme == .dark ? .white.opacity(0.92) : .primary.opacity(0.9)
        }
    }

    private var confidenceTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : .secondary
    }

    private var statusColor: Color {
        switch finding.status {
        case .pending: .orange
        case .accepted: .green
        case .rejected: .red
        }
    }

    private var confidenceText: String {
        (Double(finding.confidence) * 100)
            .formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

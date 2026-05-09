import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

struct MainView: View {
    let detector: PIIDetector
    @Bindable var pdfRedactor: PDFRedactor
    @Bindable var imageRedactor: ImageRedactor
    @Bindable var recents: RecentsStore
    @Bindable var customPatterns: CustomPatternStore
    @Binding var inputMode: InputMode
    @State private var showHome: Bool = false
    @AppStorage("HMD.recents.enabled") private var recentsEnabled: Bool = true
    @State private var saveWarningPresented = false
    @State private var customPatternsPresented = false
    @State private var diagnosticsPresented = false

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
                    recentsEnabled: $recentsEnabled,
                    onOpenPDF: openPDFAndAdd,
                    onOpenImage: openImageAndAdd,
                    onDropFile: handleDrop,
                    onOpenRecent: openRecent
                )
            } else {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

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

                    if showsReviewSidebar {
                        ReviewSidebar(
                            findings: currentReviewFindings,
                            pendingCount: currentPendingReviewCount,
                            onAcceptAll: acceptAllFindings,
                            onSelect: selectFinding,
                            onAccept: acceptFinding,
                            onReject: rejectFinding
                        )
                        .padding(EdgeInsets(top: 84, leading: 0, bottom: 18, trailing: 18))
                    }
                }

                FloatingToolbar(
                    detector: detector,
                    pdfRedactor: pdfRedactor,
                    imageRedactor: imageRedactor,
                    customPatternsCount: customPatterns.patterns.count,
                    inputMode: inputMode,
                    onManagePatterns: { customPatternsPresented = true },
                    onShowDiagnostics: { diagnosticsPresented = true },
                    onSaveRequest: requestSave
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }

            StatusPill(
                detector: detector,
                pdfRedactor: pdfRedactor,
                imageRedactor: imageRedactor,
                inputMode: inputMode,
                showingDocument: !shouldShowEmpty
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.horizontal, 22)
            .padding(.top, shouldShowEmpty ? 22 : 78)
            .allowsHitTesting(false)

            if !shouldShowEmpty {
                HomeButton { showHome = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(22)
            }
        }
        .onAppear { recents.setEnabled(recentsEnabled) }
        .onChange(of: recentsEnabled) { _, enabled in
            recents.setEnabled(enabled)
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

    private var showsReviewSidebar: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasReviewFindings
        case .image: imageRedactor.hasReviewFindings
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
            defaultFilename: "HideMyData-Regeln",
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

private struct ReviewSidebar: View {
    let findings: [ReviewFinding]
    let pendingCount: Int
    let onAcceptAll: () -> Void
    let onSelect: (UUID) -> Void
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    @State private var showOnlyPending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Treffer prüfen")
                            .font(.system(size: 16, weight: .semibold))
                        Text(headerText)
                            .font(.system(size: 12))
                            .foregroundStyle(pendingCount > 0 ? .orange : .secondary)
                    }

                    Spacer(minLength: 0)

                    if pendingCount > 0 {
                        Button("Alle bestätigen", action: onAcceptAll)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }

                Toggle("Nur offene Treffer", isOn: $showOnlyPending)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
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
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .rect(cornerRadius: 22))
    }

    private var headerText: String {
        if findings.isEmpty {
            return "Noch keine Treffer vorhanden."
        }
        if pendingCount > 0 {
            return "\(pendingCount) Treffer müssen vor dem Speichern bestätigt oder abgelehnt werden."
        }
        return "Alle Treffer wurden geprüft."
    }

    private var filteredFindings: [ReviewFinding] {
        if showOnlyPending {
            return findings.filter { $0.status == .pending }
        }
        return findings
    }
}

private struct ReviewFindingRow: View {
    let finding: ReviewFinding
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(finding.category)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        statusBadge
                    }

                    Text(finding.snippet.isEmpty ? "Ohne Textausschnitt" : finding.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        sourceBadge
                        confidenceBadge
                        if let pageIndex = finding.pageIndex {
                            Text("Seite \(pageIndex + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if finding.status == .pending {
                HStack(spacing: 8) {
                    Button("Bestätigen", action: onAccept)
                        .buttonStyle(.glassProminent)
                    Button("Ablehnen", action: onReject)
                        .buttonStyle(.glass)
                }
                .controlSize(.small)
            }
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

    private var confidenceBadge: some View {
        Text("Konf. \(confidenceText)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
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

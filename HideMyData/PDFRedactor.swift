import Foundation
import PDFKit
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
internal import UniformTypeIdentifiers

enum RedactionStyle: String, CaseIterable, Identifiable {
    case blackRectangle
    case blur

    var id: Self { self }

    var displayName: String {
        switch self {
        case .blackRectangle: return "Schwarz"
        case .blur: return "Unschärfe"
        }
    }
}

enum EditingMode: String, CaseIterable, Identifiable {
    case view
    case add
    case remove

    var id: Self { self }

    var displayName: String {
        switch self {
        case .view: return "Ansehen"
        case .add: return "Hinzufügen"
        case .remove: return "Entfernen"
        }
    }

    var systemImage: String {
        switch self {
        case .view: return "eye"
        case .add: return "plus.square"
        case .remove: return "minus.square"
        }
    }
}

@Observable
@MainActor
final class PDFRedactor {
    struct FocusTarget: Equatable {
        let pageIndex: Int
        let rect: CGRect
    }

    private struct RedactionEntry {
        let page: PDFPage
        let annotation: PDFAnnotation
        let findingID: UUID?
    }

    enum Phase: Equatable {
        case empty
        case loaded
        case detecting
        case redacted(spanCount: Int, rectCount: Int)
        case saved(URL)
        case failed(String)
    }

    var phase: Phase = .empty
    var document: PDFDocument?
    var sourceURL: URL?
    var editingMode: EditingMode = .view
    var redactionStyle: RedactionStyle = .blackRectangle {
        didSet { if oldValue != redactionStyle { restyleAllAnnotations() } }
    }
    var reviewFindings: [ReviewFinding] = []
    var focusedFindingID: UUID?
    var focusTarget: FocusTarget?
    var focusRequestID = UUID()
    var pageCount: Int = 0
    var currentPageIndex: Int = 0
    var pageNavigationRequest = UUID()
    var requestedPageIndex: Int?
    var debugEntries: [DetectionDebugEntry] = []

    private var redactionAnnotations: [RedactionEntry] = []
    private var previewAnnotations: [RedactionEntry] = []
    private let blurCache: NSCache<PDFPage, CGImage> = {
        let cache = NSCache<PDFPage, CGImage>()
        cache.countLimit = 8
        return cache
    }()
    private var detectionTask: Task<Void, Never>?

    var statusText: String {
        switch phase {
        case .empty: return "Kein Dokument"
        case .loaded:
            if redactionAnnotations.isEmpty && previewAnnotations.isEmpty { return "Geladen" }
            if !previewAnnotations.isEmpty {
                return "\(previewAnnotations.count) Markierung\(previewAnnotations.count == 1 ? "" : "en")"
            }
            return "\(redactionAnnotations.count) Schwärzung\(redactionAnnotations.count == 1 ? "" : "en")"
        case .detecting: return "PII wird erkannt…"
        case .redacted(_, let r):
            return "\(r) Bereich\(r == 1 ? "" : "e") vorbereitet"
        case .saved(let url): return "Gespeichert → \(url.lastPathComponent)"
        case .failed(let m): return "Fehler: \(m)"
        }
    }

    var hasRedactions: Bool { !redactionAnnotations.isEmpty }
    var canDetect: Bool { document != nil && phase != .detecting }
    var redactionCount: Int { redactionAnnotations.count }
    var hasReviewFindings: Bool { !reviewFindings.isEmpty }
    var pendingReviewCount: Int { reviewFindings.filter { $0.status == .pending }.count }
    var hasPendingReview: Bool { pendingReviewCount > 0 }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }

    // MARK: - Open / Save

    @discardableResult
    func openPDF() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return loadPDF(from: url)
    }

    @discardableResult
    func loadPDF(from url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else {
            phase = .failed("PDF konnte nicht geöffnet werden: \(url.lastPathComponent)")
            return false
        }
        cancelDetection()
        clearAllVisuals(silently: true)
        blurCache.removeAllObjects()
        clearReviewState()
        self.document = doc
        self.sourceURL = url
        self.pageCount = doc.pageCount
        self.currentPageIndex = 0
        self.requestedPageIndex = nil
        self.phase = .loaded
        return true
    }

    /// Load a PDF whose bytes are already in memory. Used by the recents flow so the
    /// security-scoped resource can be released as soon as the file is read, while
    /// `sourceURL` still points at the original location for save-name suggestions.
    @discardableResult
    func loadPDF(data: Data, originalURL: URL) -> Bool {
        guard let doc = PDFDocument(data: data) else {
            phase = .failed("PDF konnte nicht geöffnet werden: \(originalURL.lastPathComponent)")
            return false
        }
        cancelDetection()
        clearAllVisuals(silently: true)
        blurCache.removeAllObjects()
        clearReviewState()
        self.document = doc
        self.sourceURL = originalURL
        self.pageCount = doc.pageCount
        self.currentPageIndex = 0
        self.requestedPageIndex = nil
        self.phase = .loaded
        return true
    }

    func save() {
        guard document != nil else { return }
        let panel = NSSavePanel()
        let exportAccessory = ExportOptionsAccessoryView()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedSaveName()
        panel.accessoryView = exportAccessory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let outURL = saveSecurely(to: url, options: exportAccessory.options) {
            phase = .saved(outURL)
        } else {
            phase = .failed("Geschwärzte PDF konnte nicht gespeichert werden")
        }
    }

    // MARK: - Detection

    func detectAndRedact(using detector: PIIDetector) {
        cancelDetection()
        detectionTask = Task { [weak self] in
            await self?.runDetection(using: detector)
        }
    }

    func cancelDetection() {
        detectionTask?.cancel()
        detectionTask = nil
    }

    private func runDetection(using detector: PIIDetector) async {
        guard let doc = document else { return }
        clearAllVisuals(silently: true)
        clearReviewState()
        phase = .detecting

        var totalSpans = 0
        var totalRects = 0
        var reviewCandidates: [ReviewFindingCandidate] = []

        for pageIndex in 0..<doc.pageCount {
            if Task.isCancelled { return }
            guard let page = doc.page(at: pageIndex) else { continue }

            let pageText = page.string ?? ""
            let source: PageTextSource
            let modelInput: String
            let offsetMap: [Int]
            let trimmedPageText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldPreferOCR = trimmedPageText.isEmpty || nativeTextLikelyNeedsOCR(trimmedPageText)
            if shouldPreferOCR, let ocrPage = await ocrText(for: page), !ocrPage.combinedText.isEmpty {
                source = .ocr(ocrPage)
                let n = OCRNormalizer.normalize(ocrPage.combinedText, mode: .ocr)
                modelInput = n.text
                offsetMap = n.offsetMap
            } else if !trimmedPageText.isEmpty {
                source = .nativeText(pageText)
                let n = OCRNormalizer.normalize(pageText, mode: .native)
                modelInput = n.text
                offsetMap = n.offsetMap
            } else {
                continue
            }
            let result = await detector.detect(modelInput)
            if Task.isCancelled { return }
            switch result {
            case .failure(let err):
                phase = .failed("Erkennungsfehler auf Seite \(pageIndex + 1): \(err.localizedDescription)")
                return
            case .success(let spans):
                let supplementalContextSpans = contextualSupplementalSpans(in: source.text)
                let ocrSupplemental = source.ocrPage.map { supplementalOCRContextSpans(in: $0) } ?? ([], [])
                let visibleDebugSpans = (spans + supplementalContextSpans + ocrSupplemental.0)
                    .filter { !shouldSuppressHeaderLikeFinding($0, in: source.text) }
                var pageReviewCandidates: [ReviewFindingCandidate] = []
                debugEntries.append(
                    DetectionDebugEntry(
                        title: "Seite \(pageIndex + 1)",
                        textSourceLabel: source.debugLabel,
                        rawText: source.text,
                        normalizedText: modelInput,
                        findings: visibleDebugSpans,
                        diagnostics: PIIDetector.visiblePatternDiagnostics(for: modelInput) + ocrSupplemental.1,
                        previewDiagnostics: []
                    )
                )
                totalSpans += visibleDebugSpans.count
                var unmapped: [DetectedSpan] = []
                for span in visibleDebugSpans {
                    let (s, e) = OCRNormalizer.translateRange(
                        start: span.start, end: span.end, map: offsetMap, originalCount: source.text.count
                    )
                    let translated = DetectedSpan(
                        category: span.category, text: span.text,
                        start: s, end: e, confidence: span.confidence,
                        source: span.source
                    )
                    let rects = boundingRects(for: translated, source: source, on: page)
                    if rects.isEmpty {
                        unmapped.append(translated)
                    } else {
                        let expandedRects = expandedContextRects(
                            for: translated,
                            baseRects: rects,
                            pageText: source.text,
                            on: page
                        )
                        reviewCandidates.append(
                            ReviewFindingCandidate(
                                category: translated.category,
                                snippet: translated.text,
                                source: translated.source,
                                confidence: translated.confidence,
                                pageIndex: pageIndex,
                                rects: expandedRects
                            )
                        )
                        pageReviewCandidates.append(
                            ReviewFindingCandidate(
                                category: translated.category,
                                snippet: translated.text,
                                source: translated.source,
                                confidence: translated.confidence,
                                pageIndex: pageIndex,
                                rects: expandedRects
                            )
                        )
                        totalRects += expandedRects.count
                    }
                }
                if !unmapped.isEmpty, case .nativeText = source {
                    let recovered = await rectsViaOCRFallback(for: unmapped, on: page)
                    let grouped = Dictionary(grouping: recovered, by: \.1.id)
                    for span in unmapped {
                        guard let matches = grouped[span.id], !matches.isEmpty else { continue }
                        let rects = expandedContextRects(
                            for: span,
                            baseRects: matches.map(\.0),
                            pageText: source.text,
                            on: page
                        )
                        reviewCandidates.append(
                            ReviewFindingCandidate(
                                category: span.category,
                                snippet: span.text,
                                source: span.source,
                                confidence: span.confidence,
                                pageIndex: pageIndex,
                                rects: rects
                            )
                        )
                        pageReviewCandidates.append(
                            ReviewFindingCandidate(
                                category: span.category,
                                snippet: span.text,
                                source: span.source,
                                confidence: span.confidence,
                                pageIndex: pageIndex,
                                rects: rects
                            )
                        )
                        totalRects += rects.count
                    }
                }

                for span in supplementalContextSpans + ocrSupplemental.0 {
                    let rects = boundingRects(for: span, source: source, on: page)
                    guard !rects.isEmpty else { continue }
                    reviewCandidates.append(
                        ReviewFindingCandidate(
                            category: span.category,
                            snippet: span.text,
                            source: span.source,
                            confidence: span.confidence,
                            pageIndex: pageIndex,
                            rects: deduplicatedRects(rects)
                        )
                    )
                    pageReviewCandidates.append(
                        ReviewFindingCandidate(
                            category: span.category,
                            snippet: span.text,
                            source: span.source,
                            confidence: span.confidence,
                            pageIndex: pageIndex,
                            rects: deduplicatedRects(rects)
                        )
                    )
                    totalRects += rects.count
                }

                if let entryIndex = debugEntries.indices.last {
                    let entry = debugEntries[entryIndex]
                    debugEntries[entryIndex] = DetectionDebugEntry(
                        title: entry.title,
                        textSourceLabel: entry.textSourceLabel,
                        rawText: entry.rawText,
                        normalizedText: entry.normalizedText,
                        findings: entry.findings,
                        diagnostics: entry.diagnostics,
                        previewDiagnostics: previewDiagnosticsLines(for: pageReviewCandidates)
                    )
                }
            }
        }

        totalRects = 0
        let reviewProjections = ReviewFindingCompactor.compact(reviewCandidates)
        for projection in reviewProjections {
            reviewFindings.append(projection.finding)
            guard let pageIndex = projection.finding.pageIndex,
                  let page = doc.page(at: pageIndex)
            else { continue }
            for rect in projection.rects {
                addPreview(rect: rect, on: page, findingID: projection.finding.id)
                totalRects += 1
            }
        }

        if let firstPending = reviewFindings.first(where: { $0.status == .pending }) {
            selectFinding(firstPending.id)
        }
        phase = .redacted(spanCount: totalSpans, rectCount: totalRects)
    }

    private enum PageTextSource {
        case nativeText(String)
        case ocr(OCRPage)

        var text: String {
            switch self {
            case .nativeText(let s): return s
            case .ocr(let p): return p.combinedText
            }
        }

        var debugLabel: String {
            switch self {
            case .nativeText: return "PDF-Text"
            case .ocr: return "Apple Vision OCR"
            }
        }

        var ocrPage: OCRPage? {
            switch self {
            case .nativeText: return nil
            case .ocr(let page): return page
            }
        }
    }

    private func ocrText(for page: PDFPage) async -> OCRPage? {
        guard let cg = renderPageToCGImage(page, scale: 2) else { return nil }
        return try? await OCREngine.recognize(cg)
    }

    private func shouldSuppressHeaderLikeFinding(_ span: DetectedSpan, in pageText: String) -> Bool {
        let cleanedSnippet = span.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSnippet.isEmpty else { return false }

        let normalizedSnippet = cleanedSnippet.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let compactSnippet = cleanedSnippet
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }

        let isPostalCity = cleanedSnippet.range(
            of: #"^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#,
            options: .regularExpression
        ) != nil
        let isStreetAddress = span.category == "private_address" &&
            cleanedSnippet.range(
                of: #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#,
                options: .regularExpression
            ) != nil
        let isBareCityToken = span.category == "private_person" && compactSnippet.range(
            of: #"^[a-zäöüß]{4,}$"#,
            options: .regularExpression
        ) != nil
        let isLikelyPersonName = span.category == "private_person" &&
            cleanedSnippet.range(
                of: #"(?i)^(?:herr|frau)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$|^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}(?:,\s*(?:CEO|CFO|COO|CTO|CMO))?$"#,
                options: .regularExpression
            ) != nil
        guard isPostalCity || isBareCityToken || isStreetAddress || isLikelyPersonName else { return false }

        let lines = pageText.components(separatedBy: .newlines)
        let headerKeywords = [
            "finanzamt", "finanzkasse", "moltkestr", "moltkestra", "tel", "zi.nr",
            "steuernummer", "idnr", "deutsche post", "geschäftsführung",
            "geschaftsfuhrung", "geschäftsführer", "geschaftsfuhrer",
            "handelsregister", "amtsgericht", "bankverbindung", "onlinebuchung",
            "reisebestätigung", "reisebestatigung"
        ]
        let senderKeywords = [
            "gmbh", "mbh", "ag", "ug", "kg", "ohg", "gbr", "kundin", "kunde"
        ]
        let companyHeaderPresent = lines.prefix(6).contains { line in
            let normalized = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return senderKeywords.contains(where: { normalized.contains($0) })
        }
        let firstRecipientIndex = lines.firstIndex { line in
            looksLikeRecipientMarkerLine(line)
        }

        for (index, line) in lines.enumerated() {
            let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let compactLine = normalizedLine.filter { $0.isLetter || $0.isNumber }
            guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) ||
                    (!compactSnippet.isEmpty && compactLine.contains(compactSnippet))
            else { continue }

            if (isPostalCity || isStreetAddress) && looksLikeOrganizationHeaderLine(line) {
                return true
            }

            let contextStart = max(0, index - 2)
            let contextEnd = min(lines.count - 1, index + 2)
            let context = lines[contextStart...contextEnd]
                .joined(separator: "\n")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            if headerKeywords.contains(where: { context.contains($0) }) {
                return true
            }
            if isLikelyPersonName,
               context.contains("geschaftsfuhrung") || context.contains("geschäftsführung") ||
                context.contains("ceo") || context.contains("cfo") ||
                context.contains("geschäftsführer") || context.contains("geschaftsfuhrer") {
                return true
            }
            if let firstRecipientIndex,
               index < firstRecipientIndex,
               senderKeywords.contains(where: { context.contains($0) }) {
                return true
            }
            if companyHeaderPresent,
               isEmbeddedSenderBlockLine(in: lines, at: index, isStreetAddress: isStreetAddress, isPostalCity: isPostalCity) {
                return true
            }
            if isPostalCity,
               context.range(of: #"\b\d{2}\.\d{2}\.\d{4}\b"#, options: .regularExpression) != nil {
                return true
            }
            if isPostalCity,
               context.range(of: #"\(?\d{3,5}\)?[ /-]?\d{2,5}[-/]\d{2,5}"#, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    private func isEmbeddedSenderBlockLine(
        in lines: [String],
        at index: Int,
        isStreetAddress: Bool,
        isPostalCity: Bool
    ) -> Bool {
        guard index >= 0, index < lines.count else { return false }

        let previousIndex = nearestNonEmptyLineIndex(in: lines, before: index)
        let nextIndex = nearestNonEmptyLineIndex(in: lines, after: index)
        let hasRecipientMarkerNearby = (max(0, index - 2)...min(lines.count - 1, index + 1)).contains { nearbyIndex in
            looksLikeRecipientMarkerLine(lines[nearbyIndex])
        }
        guard !hasRecipientMarkerNearby else { return false }

        let senderContextKeywords = ["vertrieb", "kundenservice", "kontakt", "tarif", "online", "gmbh", "ag", "mbh"]
        let previousLine = previousIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let normalizedPrevious = previousLine.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let previousLooksSenderLike =
            previousLine.contains(".") ||
            previousLine.contains(":") ||
            senderContextKeywords.contains(where: { normalizedPrevious.contains($0) })

        if isStreetAddress,
           let nextIndex,
           looksLikePostalCityLine(lines[nextIndex]),
           previousLooksSenderLike {
            return true
        }

        if isPostalCity,
           let previousIndex,
           looksLikeGermanStreetLine(lines[previousIndex]) {
            let senderPreludeIndex = nearestNonEmptyLineIndex(in: lines, before: previousIndex)
            let senderPrelude = senderPreludeIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let normalizedPrelude = senderPrelude.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if senderPrelude.contains(".") ||
                senderPrelude.contains(":") ||
                senderContextKeywords.contains(where: { normalizedPrelude.contains($0) }) {
                return true
            }
        }

        return false
    }

    private func nearestNonEmptyLineIndex(in lines: [String], before index: Int) -> Int? {
        guard index > 0 else { return nil }
        for candidate in stride(from: index - 1, through: 0, by: -1) {
            if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    private func nearestNonEmptyLineIndex(in lines: [String], after index: Int) -> Int? {
        guard index + 1 < lines.count else { return nil }
        for candidate in (index + 1)..<lines.count {
            if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    private func nativeTextLikelyNeedsOCR(_ text: String) -> Bool {
        let ocrLikeNormalized = OCRNormalizer.normalize(text, mode: .ocr).text
        let nativeNormalized = OCRNormalizer.normalize(text, mode: .native).text
        let rawCount = max(text.count, 1)
        let compactedCount = max(0, nativeNormalized.count - ocrLikeNormalized.count)
        let compactionRatio = Double(compactedCount) / Double(rawCount)

        let spacedRunCount = matches(
            for: #"(?u)(?:\b[\p{L}\p{N}]\s+){3,}[\p{L}\p{N}]\b"#,
            in: text
        )
        let suspiciousSymbolCount = text.filter { "^�".contains($0) }.count

        if spacedRunCount >= 3 { return true }
        if spacedRunCount >= 2, compactionRatio > 0.05 { return true }
        if compactionRatio > 0.12 { return true }
        if suspiciousSymbolCount >= 2, compactionRatio > 0.04 { return true }
        return false
    }

    private func contextualSupplementalSpans(in text: String) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []
        let lines = pageTextLines(in: text)

        func appendSpan(for line: PageTextLine, category: String) {
            let matched = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !matched.isEmpty,
                  let swiftRange = Range(line.range, in: text)
            else { return }
            let start = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: swiftRange.upperBound)
            spans.append(
                DetectedSpan(
                    category: category,
                    text: matched,
                    start: start,
                    end: end,
                    confidence: 0.98,
                    source: .pattern
                )
            )
        }

        func appendSpan(for line: PageTextLine, matchedText: String, category: String) {
            let lineText = line.text
            let trimmedMatch = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMatch.isEmpty,
                  let localRange = lineText.range(
                    of: trimmedMatch,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  ),
                  let lineRange = Range(line.range, in: text)
            else { return }

            let start = text.distance(from: text.startIndex, to: lineRange.lowerBound)
                + lineText.distance(from: lineText.startIndex, to: localRange.lowerBound)
            let end = start + lineText.distance(from: localRange.lowerBound, to: localRange.upperBound)
            spans.append(
                DetectedSpan(
                    category: category,
                    text: trimmedMatch,
                    start: start,
                    end: end,
                    confidence: 0.98,
                    source: .pattern
                )
            )
        }

        func looksLikeHonorificLine(_ text: String) -> Bool {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        func appendLabeledAddressBlock(startingAt index: Int, includeLabelAsAddress: Bool = true) {
            guard lines.indices.contains(index) else { return }
            if includeLabelAsAddress {
                appendSpan(for: lines[index], category: "private_address")
            }

            let searchEnd = min(lines.count, index + 8)
            var blockIndices: [Int] = []
            var previousComparable = ""
            for cursor in (index + 1)..<searchEnd {
                let cleaned = lines[cursor].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                let comparable = normalizedComparableText(cleaned)
                if comparable == previousComparable, !comparable.isEmpty { continue }
                blockIndices.append(cursor)
                previousComparable = comparable
                if looksLikePostalCityLine(cleaned) { break }
            }

            guard !blockIndices.isEmpty else { return }

            var dataStart = 0
            if let firstIndex = blockIndices.first, looksLikeHonorificLine(lines[firstIndex].text) {
                appendSpan(for: lines[firstIndex], category: "private_person")
                dataStart = 1
            }

            for relativeIndex in dataStart..<blockIndices.count {
                let actualIndex = blockIndices[relativeIndex]
                let cleaned = lines[actualIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if relativeIndex == dataStart {
                    appendSpan(for: lines[actualIndex], category: "private_person")
                    continue
                }
                if looksLikeGermanStreetLine(cleaned) || looksLikePostalCityLine(cleaned) {
                    appendSpan(for: lines[actualIndex], category: "private_address")
                }
            }
        }

        for (index, line) in lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let inlineMatch = inlineContextPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: inlineMatch, category: "private_person")
                continue
            }

            if let salutationMatch = inlineSalutationPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: salutationMatch, category: "private_person")
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Abweichender Ansprechpartner:") {
                appendSpan(for: line, category: "private_person")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_person") }
                if index + 2 < lines.count { appendSpan(for: lines[index + 2], category: "private_email") }
                if index + 3 < lines.count { appendSpan(for: lines[index + 3], category: "private_phone") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Lieferadresse:") ||
                cleaned.localizedCaseInsensitiveContains("Lieferanschrift:") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Versicherungsnehmer") ||
                cleaned.localizedCaseInsensitiveContains("Darlehensnehmer") ||
                cleaned.localizedCaseInsensitiveContains("Anschlussinhaber") {
                appendLabeledAddressBlock(startingAt: index, includeLabelAsAddress: false)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Lieferstelle") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Ihre Lieferadresse") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Postanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Korrespondenzanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Objektanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Nutzungsadresse") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Hier liefern wir Ihren Strom hin") {
                appendSpan(for: line, category: "private_address")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_address") }
                if index + 2 < lines.count { appendSpan(for: lines[index + 2], category: "private_address") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Hierauf stellen wir Ihre Rechnung aus") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Rechnungsanschrift") {
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Schriftverkehr") {
                appendSpan(for: line, category: "private_address")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_address") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Für Rückfragen") ||
                cleaned.localizedCaseInsensitiveContains("Fur Ruckfragen") ||
                cleaned.localizedCaseInsensitiveContains("Rueckfragen") {
                appendSpan(for: line, category: "private_person")
            }

            if cleaned.localizedCaseInsensitiveContains("Hier erreichen wir Sie bei Rückfragen") ||
                cleaned.localizedCaseInsensitiveContains("Hier erreichen wir Sie bei Rueckfragen") {
                if let contactNameLine = nativeContactNameLine(in: lines, from: index) {
                    if contactNameLine.lineIndex == index {
                        appendSpan(
                            for: lines[index],
                            matchedText: contactNameLine.matchedText,
                            category: "private_person"
                        )
                    } else {
                        appendSpan(for: lines[contactNameLine.lineIndex], category: "private_person")
                    }
                }
            }

            if looksLikeNativeRecipientNameLine(cleaned),
               let recipientBlock = resolveNativeRecipientBlock(in: lines, nameIndex: index) {
                appendSpan(for: line, category: "private_person")
                appendSpan(for: lines[recipientBlock.streetIndex], category: "private_address")
                appendSpan(for: lines[recipientBlock.postalCityIndex], category: "private_address")
            }
        }

        return deduplicatedSpans(spans)
    }

    private func nativeContactNameLine(in lines: [PageTextLine], from anchorIndex: Int) -> (lineIndex: Int, matchedText: String)? {
        guard !lines.isEmpty else { return nil }
        let startIndex = max(0, anchorIndex)
        let endIndex = min(lines.count - 1, startIndex + 4)

        for index in startIndex...endIndex {
            let cleaned = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let inlineMatch = inlineContextPersonName(in: cleaned) {
                return (index, inlineMatch)
            }

            if looksLikeNativeRecipientNameLine(cleaned) {
                return (index, cleaned)
            }
        }

        return nil
    }

    private func inlineContextPersonName(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = #"(?i)\b(?:name|bestellt\s+durch|besteller(?:in)?|kund(?:e|in)|kontoinhaber)\s*:\s*([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: normalized) else {
            return nil
        }
        return String(normalized[range])
    }

    private func inlineSalutationPersonName(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let patterns = [
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Frau|Herr)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { continue }
            return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        }
        return nil
    }

    private func looksLikeNativeRecipientNameLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let personPattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#
        return cleaned.range(of: personPattern, options: .regularExpression) != nil
    }

    private func resolveNativeRecipientBlock(in lines: [PageTextLine], nameIndex: Int) -> (streetIndex: Int, postalCityIndex: Int)? {
        let searchEnd = min(lines.count, nameIndex + 4)
        guard nameIndex + 1 < searchEnd else { return nil }

        for streetIndex in (nameIndex + 1)..<searchEnd {
            let streetText = lines[streetIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !streetText.isEmpty, looksLikeGermanStreetLine(streetText) else { continue }

            for cityIndex in (streetIndex + 1)..<searchEnd {
                let cityText = lines[cityIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cityText.isEmpty else { continue }
                if looksLikePostalCityLine(cityText) {
                    return (streetIndex, cityIndex)
                }
            }
        }

        return nil
    }

    private func hasNativeRecipientContext(in lines: [PageTextLine], around index: Int) -> Bool {
        let start = max(0, index - 2)
        let end = min(lines.count - 1, index + 1)
        let context = lines[start...end]
            .map(\.text)
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let markers = [
            "eheleute",
            "herr",
            "frau",
            "kundin",
            "kunde",
            "lieferadresse",
            "ihre lieferadresse",
            "hier liefern wir ihren strom hin",
            "hierauf stellen wir ihre rechnung aus",
            "versicherungsnehmer",
            "darlehensnehmer",
            "anschlussinhaber",
            "postanschrift",
            "korrespondenzanschrift",
            "objektanschrift",
            "nutzungsadresse",
            "rechnungsanschrift",
            "lieferstelle"
        ]
        return markers.contains { context.contains($0) }
    }

    private func supplementalOCRContextSpans(in page: OCRPage) -> ([DetectedSpan], [String]) {
        var spans: [DetectedSpan] = []
        var diagnostics: [String] = []

        func appendLine(_ index: Int, category: String) {
            guard let span = page.lineSpan(at: index, category: category) else { return }
            spans.append(span)
        }

        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard looksLikeWindowRecipientNameLine(cleaned),
                  hasNearbyOrganizationHeader(in: page, before: index),
                  let block = resolveWindowRecipientBlock(in: page, nameIndex: index)
            else { continue }

            diagnostics.append("PDF OCR supplemental recipient block at line \(index): \(cleaned)")
            appendLine(index, category: "private_person")
            for streetIndex in (index + 1)..<block {
                let streetText = page.lines[streetIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeGermanStreetLine(streetText) {
                    appendLine(streetIndex, category: "private_address")
                }
            }
            appendLine(block, category: "private_address")
        }

        return (deduplicatedSpans(spans), diagnostics)
    }

    private func looksLikeWindowRecipientNameLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func hasNearbyOrganizationHeader(in page: OCRPage, before index: Int) -> Bool {
        guard index > 0 else { return false }
        let start = max(0, index - 3)
        for previousIndex in start..<index {
            if looksLikeOrganizationHeaderLine(page.lines[previousIndex].text) {
                return true
            }
        }
        return false
    }

    private func looksLikeOrganizationHeaderLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func resolveWindowRecipientBlock(in page: OCRPage, nameIndex: Int) -> Int? {
        let searchEnd = min(page.lines.count, nameIndex + 5)
        guard nameIndex + 1 < searchEnd else { return nil }

        var foundStreet = false
        for lineIndex in (nameIndex + 1)..<searchEnd {
            let text = page.lines[lineIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if looksLikeGermanStreetLine(text) {
                foundStreet = true
                continue
            }
            if foundStreet, looksLikePostalCityLine(text) {
                return lineIndex
            }
        }

        return nil
    }

    private func looksLikeGermanStreetLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikePostalCityLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func previewDiagnosticsLines(for candidates: [ReviewFindingCandidate]) -> [String] {
        guard !candidates.isEmpty else {
            return ["Preview candidates: 0", "Preview detail: <none>"]
        }

        var lines: [String] = []
        lines.append("Preview candidates: \(candidates.count)")
        for candidate in candidates {
            let rectSummary = candidate.rects.enumerated().map { index, rect in
                "\(index): x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))"
            }.joined(separator: " | ")
            lines.append("[\(candidate.category)] \(candidate.snippet)")
            lines.append("  Source: \(candidate.source.label) · \(Int(candidate.confidence * 100))%")
            lines.append("  Rects: \(rectSummary.isEmpty ? "<none>" : rectSummary)")
        }
        return lines
    }

    private func expandedContextRects(
        for span: DetectedSpan,
        baseRects: [CGRect],
        pageText: String,
        on page: PDFPage
    ) -> [CGRect] {
        guard span.category == "private_person" || span.category == "private_address" else {
            return baseRects
        }

        var expanded = baseRects
        expanded.append(contentsOf: contextualRedactionLabelRects(for: span, in: pageText, on: page))
        return deduplicatedRects(expanded)
    }

    private struct PageTextLine {
        let text: String
        let range: NSRange
    }

    private func contextualRedactionLabelRects(
        for span: DetectedSpan,
        in pageText: String,
        on page: PDFPage
    ) -> [CGRect] {
        let compactSpan = normalizedComparableText(span.text)
        guard !compactSpan.isEmpty,
              let spanRange = nsRange(start: span.start, end: span.end, in: pageText)
        else {
            return []
        }

        let lines = pageTextLines(in: pageText)
        var matches: [CGRect] = []
        var seen = Set<String>()

        for (index, line) in lines.enumerated() {
            let cleanedLine = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedLine.isEmpty else { continue }

            let compactLine = normalizedComparableText(cleanedLine)
            let lineContainsSpan = compactLine.contains(compactSpan)
            let overlapsSpanRange = NSIntersectionRange(line.range, spanRange).length > 0
            guard lineContainsSpan || overlapsSpanRange else { continue }

            if isRedactionContextLabelLine(cleanedLine), seen.insert(cleanedLine).inserted {
                matches.append(contentsOf: rects(for: line, on: page))
            }

            for offset in 1...3 {
                let previousIndex = index - offset
                guard previousIndex >= 0 else { break }
                let previousLine = lines[previousIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if previousLine.isEmpty { continue }
                if isRedactionContextLabelLine(previousLine), seen.insert(previousLine).inserted {
                    matches.append(contentsOf: rects(for: lines[previousIndex], on: page))
                }
                break
            }
        }

        return deduplicatedRects(matches)
    }

    private func pageTextLines(in text: String) -> [PageTextLine] {
        let nsText = text as NSString
        var lines: [PageTextLine] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines]
        ) { _, substringRange, _, _ in
            let lineText = nsText.substring(with: substringRange)
            lines.append(PageTextLine(text: lineText, range: substringRange))
        }
        return lines
    }

    private func rects(for line: PageTextLine, on page: PDFPage) -> [CGRect] {
        guard let selection = page.selection(for: line.range) else {
            let occurrence = occurrenceIndex(of: line.text, in: page.string ?? "", start: line.range.location)
            return rectsByTextSearch(needle: line.text, occurrenceIndex: occurrence, on: page)
        }
        let directRects = perLineRects(of: selection, on: page)
        if !directRects.isEmpty {
            return directRects
        }
        let occurrence = occurrenceIndex(of: line.text, in: page.string ?? "", start: line.range.location)
        return rectsByTextSearch(needle: line.text, occurrenceIndex: occurrence, on: page)
    }

    private func isRedactionContextLabelLine(_ line: String) -> Bool {
        let normalizedLine = line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let markers = [
            "abweichender ansprechpartner",
            "lieferadresse",
            "versicherungsnehmer",
            "darlehensnehmer",
            "anschlussinhaber",
            "lieferstelle",
            "postanschrift",
            "korrespondenzanschrift",
            "objektanschrift",
            "nutzungsadresse",
            "rechnungsanschrift",
            "schriftverkehr",
            "fuer rueckfragen",
            "fur ruckfragen",
            "rueckfragen",
            "ruckfragen",
            "hier erreichen wir sie bei rueckfragen",
            "hier liefern wir ihren strom hin",
            "hierauf stellen wir ihre rechnung aus"
        ]
        return markers.contains { normalizedLine.contains($0) }
    }

    private func looksLikeRecipientMarkerLine(_ line: String) -> Bool {
        let cleaned = line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let explicitPrefixes = [
            "kundin:", "kunde:", "lieferadresse:", "schriftverkehr", "kontoinhaber:",
            "abweichender ansprechpartner:", "bestellt durch:", "besteller:", "bestellerin:", "name:",
            "eheleute", "herr", "frau",
            "versicherungsnehmer", "darlehensnehmer", "postanschrift",
            "korrespondenzanschrift", "objektanschrift", "rechnungsanschrift",
            "lieferstelle", "anschlussinhaber", "nutzungsadresse"
        ]
        return explicitPrefixes.contains(where: { cleaned.hasPrefix($0) })
    }

    private func normalizedComparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private func deduplicatedRects(_ rects: [CGRect]) -> [CGRect] {
        var unique: [CGRect] = []
        for rect in rects {
            let standardized = rect.standardized
            guard standardized.width > 0.5, standardized.height > 0.5 else { continue }
            let alreadyPresent = unique.contains { existing in
                abs(existing.minX - standardized.minX) < 0.5 &&
                abs(existing.minY - standardized.minY) < 0.5 &&
                abs(existing.width - standardized.width) < 0.5 &&
                abs(existing.height - standardized.height) < 0.5
            }
            if !alreadyPresent {
                unique.append(standardized)
            }
        }
        return unique
    }

    private func deduplicatedSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var seen = Set<String>()
        var unique: [DetectedSpan] = []
        for span in spans {
            let key = "\(span.category)::\(span.start)::\(span.end)::\(span.text)"
            if seen.insert(key).inserted {
                unique.append(span)
            }
        }
        return unique
    }

    private func matches(for pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func renderPageToCGImage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pixelWidth = Int(pageBounds.width * scale)
        let pixelHeight = Int(pageBounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        for ann in detached { page.removeAnnotation(ann) }
        defer { for ann in detached { page.addAnnotation(ann) } }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: - Annotations

    enum RedactionSource { case auto, manual }

    @discardableResult
    func addRedaction(
        rect: CGRect,
        on page: PDFPage,
        source: RedactionSource = .manual,
        findingID: UUID? = nil,
        rectIsPreNormalized: Bool = false
    ) -> PDFAnnotation {
        let padded = rectIsPreNormalized ? rect : normalizedDisplayRect(for: rect, on: page)
        let ann: PDFAnnotation
        switch redactionStyle {
        case .blackRectangle:
            let blackAnn = BlackRedactionAnnotation(bounds: padded, forType: .square, withProperties: nil)
            blackAnn.border = nil
            ann = blackAnn
        case .blur:
            let blurAnn = BlurRedactionAnnotation(bounds: padded, forType: .square, withProperties: nil)
            blurAnn.border = nil
            blurAnn.blurredPageImage = blurredImage(for: page)
            blurAnn.pageMediaBoxRect = page.bounds(for: .mediaBox)
            ann = blurAnn
        }
        page.addAnnotation(ann)
        redactionAnnotations.append(RedactionEntry(page: page, annotation: ann, findingID: findingID))

        let count = redactionAnnotations.count
        switch phase {
        case .loaded, .saved:
            if source == .manual { phase = .redacted(spanCount: 0, rectCount: count) }
        case .redacted:
            phase = .redacted(spanCount: 0, rectCount: count)
        default:
            break
        }
        return ann
    }

    @discardableResult
    private func addPreview(rect: CGRect, on page: PDFPage, findingID: UUID) -> PDFAnnotation {
        let padded = normalizedDisplayRect(for: rect, on: page)
        let annotation = PreviewRedactionAnnotation(bounds: padded, forType: .square, withProperties: nil)
        annotation.border = nil
        if let finding = reviewFindings.first(where: { $0.id == findingID }) {
            annotation.tintColor = previewColor(for: finding.category)
        }
        page.addAnnotation(annotation)
        previewAnnotations.append(RedactionEntry(page: page, annotation: annotation, findingID: findingID))
        return annotation
    }

    func removeRedaction(_ ann: PDFAnnotation, on page: PDFPage) {
        page.removeAnnotation(ann)
        let removed = redactionAnnotations.first { $0.annotation === ann }
        redactionAnnotations.removeAll { $0.annotation === ann }
        if let findingID = removed?.findingID {
            syncFindingStateAfterRedactionRemoval(findingID: findingID)
        }
        if redactionAnnotations.isEmpty, document != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionAnnotations.count)
        }
    }

    func isRedaction(_ ann: PDFAnnotation) -> Bool {
        redactionAnnotations.contains { $0.annotation === ann }
    }

    func acceptFinding(_ id: UUID) {
        promotePreviewToRedaction(for: id)
        updateFinding(id) { $0.status = .accepted }
        selectFinding(id)
    }

    func acceptAllFindings() {
        let pendingIDs = reviewFindings
            .filter { $0.status == .pending }
            .map(\.id)
        for id in pendingIDs {
            acceptFinding(id)
        }
    }

    func rejectFinding(_ id: UUID) {
        removePreviews(for: id)
        updateFinding(id) { $0.status = .rejected }
        if focusedFindingID == id {
            focusedFindingID = nil
            focusTarget = nil
        }
        if redactionAnnotations.isEmpty, document != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionAnnotations.count)
        }
    }

    func selectFinding(_ id: UUID) {
        focusedFindingID = id
        focusTarget = nil
        guard let target = firstFocusTarget(for: id) else { return }
        currentPageIndex = target.pageIndex
        focusTarget = target
        focusRequestID = UUID()
    }

    func goToPreviousPage() {
        goToPage(currentPageIndex - 1)
    }

    func goToNextPage() {
        goToPage(currentPageIndex + 1)
    }

    func goToPage(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pageCount else { return }
        currentPageIndex = pageIndex
        requestedPageIndex = pageIndex
        pageNavigationRequest = UUID()
    }

    func updateVisiblePage(index: Int) {
        guard index >= 0 else { return }
        currentPageIndex = index
    }

    func clearRedactions() {
        cancelDetection()
        clearAllVisuals(silently: false)
        clearReviewState()
    }

    private func clearAllVisuals(silently: Bool) {
        for entry in redactionAnnotations {
            entry.page.removeAnnotation(entry.annotation)
        }
        for entry in previewAnnotations {
            entry.page.removeAnnotation(entry.annotation)
        }
        redactionAnnotations.removeAll()
        previewAnnotations.removeAll()
        if !silently, document != nil { phase = .loaded }
    }

    private func restyleAllAnnotations() {
        let priorPhase = phase
        let snapshot = redactionAnnotations
        redactionAnnotations.removeAll()
        for entry in snapshot {
            let bounds = entry.annotation.bounds
            entry.page.removeAnnotation(entry.annotation)
            addRedaction(rect: bounds, on: entry.page, source: .auto, findingID: entry.findingID)
        }
        phase = priorPhase
    }

    private func clearReviewState() {
        reviewFindings.removeAll()
        focusedFindingID = nil
        focusTarget = nil
        pageCount = document?.pageCount ?? 0
        currentPageIndex = 0
        requestedPageIndex = nil
        debugEntries.removeAll()
    }

    private func removeRedactions(for findingID: UUID) {
        let matching = redactionAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        redactionAnnotations.removeAll { $0.findingID == findingID }
    }

    private func removePreviews(for findingID: UUID) {
        let matching = previewAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        previewAnnotations.removeAll { $0.findingID == findingID }
    }

    private func promotePreviewToRedaction(for findingID: UUID) {
        let matches = previewAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }
        previewAnnotations.removeAll { $0.findingID == findingID }
        for entry in matches {
            let page = entry.page
            let rect = entry.annotation.bounds
            page.removeAnnotation(entry.annotation)
            addRedaction(rect: rect, on: page, source: .auto, findingID: findingID, rectIsPreNormalized: true)
        }
    }

    private func syncFindingStateAfterRedactionRemoval(findingID: UUID) {
        guard !redactionAnnotations.contains(where: { $0.findingID == findingID }) else { return }
        updateFinding(findingID) {
            if $0.status == .pending {
                $0.status = .rejected
            }
        }
    }

    private func updateFinding(_ id: UUID, mutate: (inout ReviewFinding) -> Void) {
        guard let index = reviewFindings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&reviewFindings[index])
    }

    private func firstFocusTarget(for findingID: UUID) -> FocusTarget? {
        guard let doc = document,
              let entry = (previewAnnotations + redactionAnnotations).first(where: { $0.findingID == findingID })
        else { return nil }
        let pageIndex = doc.index(for: entry.page)
        guard pageIndex >= 0 else { return nil }
        return FocusTarget(pageIndex: pageIndex, rect: entry.annotation.bounds)
    }

    func normalizedDisplayRect(for rect: CGRect, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let workingRect = rect.standardized
        guard redactionStyle == .blackRectangle else {
            return workingRect.insetBy(dx: -1, dy: -1).intersection(pageBounds)
        }

        let targetHeight = max(12, round(workingRect.height + 4))
        let centerY = workingRect.midY
        let adjusted = CGRect(
            x: workingRect.minX - 1,
            y: centerY - (targetHeight / 2),
            width: workingRect.width + 2,
            height: targetHeight
        )
        return adjusted.intersection(pageBounds)
    }

    private func previewColor(for category: String) -> NSColor {
        switch category.lowercased() {
        case "private_email", "kontakt":
            return .systemGreen
        case "private_address", "adressblock", "adresse":
            return .systemRed
        case "account_number":
            return NSColor.systemYellow.blended(withFraction: 0.28, of: .systemOrange) ?? .systemYellow
        case "private_phone":
            return .systemTeal
        case "private_person":
            return .systemBlue
        case "private_date":
            return .systemPurple
        default:
            return .systemOrange
        }
    }

    // MARK: - Bounding rects via character offsets (with text-search fallback)

    private func boundingRects(for span: DetectedSpan, source: PageTextSource, on page: PDFPage) -> [CGRect] {
        switch source {
        case .nativeText(let pageText):
            if span.start >= 0,
               span.end > span.start,
               let utf16Range = nsRange(start: span.start, end: span.end, in: pageText),
               let selection = page.selection(for: utf16Range) {
                let rects = perLineRects(of: selection, on: page)
                if !rects.isEmpty { return rects }
            }
            let occurrence = occurrenceIndex(of: span.text, in: pageText, start: span.start)
            let textSearchRects = rectsByTextSearch(
                needle: span.text,
                occurrenceIndex: occurrence,
                on: page
            )
            if !textSearchRects.isEmpty { return textSearchRects }

            if span.category == "private_person",
               span.text.localizedCaseInsensitiveContains(" und "),
               let occurrenceIndex = occurrence {
                let fallbackRects = rectsByConjoinedNameSearch(
                    needle: span.text,
                    occurrenceIndex: occurrenceIndex,
                    on: page
                )
                if !fallbackRects.isEmpty { return fallbackRects }
            }

            return []

        case .ocr(let ocrPage):
            let normRects = ocrPage.normalizedBoxes(start: span.start, end: span.end)
            let pageBounds = page.bounds(for: .mediaBox)
            return normRects.map { norm in
                CGRect(
                    x: norm.minX * pageBounds.width,
                    y: norm.minY * pageBounds.height,
                    width: norm.width * pageBounds.width,
                    height: norm.height * pageBounds.height
                )
            }
        }
    }

    private func nsRange(start: Int, end: Int, in text: String) -> NSRange? {
        guard start <= text.count, end <= text.count, start <= end else { return nil }
        let s = text.index(text.startIndex, offsetBy: start)
        let e = text.index(text.startIndex, offsetBy: end)
        let utf16Start = text.utf16.distance(from: text.utf16.startIndex, to: s.samePosition(in: text.utf16) ?? text.utf16.startIndex)
        let utf16End = text.utf16.distance(from: text.utf16.startIndex, to: e.samePosition(in: text.utf16) ?? text.utf16.startIndex)
        return NSRange(location: utf16Start, length: utf16End - utf16Start)
    }

    private func perLineRects(of selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        var rects: [CGRect] = []
        for line in selection.selectionsByLine() {
            for selPage in line.pages where selPage === page {
                let bounds = line.bounds(for: selPage)
                if bounds.width > 0.5 && bounds.height > 0.5 {
                    rects.append(bounds)
                }
            }
        }
        return rects
    }

    private func rectsByTextSearch(needle: String, occurrenceIndex: Int? = nil, on page: PDFPage) -> [CGRect] {
        guard !needle.isEmpty else { return [] }
        if let occurrenceIndex,
           let occurrenceRects = rectsByOccurrenceSearch(needle: needle, occurrenceIndex: occurrenceIndex, on: page),
           !occurrenceRects.isEmpty {
            return occurrenceRects
        }

        guard let doc = page.document else { return [] }
        var rects: [CGRect] = []
        for selection in doc.findString(needle, withOptions: [.caseInsensitive]) {
            rects.append(contentsOf: perLineRects(of: selection, on: page))
        }
        return rects
    }

    private func rectsByOccurrenceSearch(needle: String, occurrenceIndex: Int, on page: PDFPage) -> [CGRect]? {
        let matches = selections(for: needle, on: page)
        guard matches.indices.contains(occurrenceIndex) else { return nil }
        return matches[occurrenceIndex].rects
    }

    private func occurrenceIndex(of needle: String, in text: String, start: Int) -> Int? {
        guard !needle.isEmpty, start >= 0, start <= text.count else { return nil }
        let prefixEnd = text.index(text.startIndex, offsetBy: start)
        let prefix = String(text[..<prefixEnd])
        var count = 0
        var searchStart = prefix.startIndex
        while let range = prefix.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<prefix.endIndex
        ) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private func rectsByConjoinedNameSearch(needle: String, occurrenceIndex: Int, on page: PDFPage) -> [CGRect] {
        let separators = [" und ", " UND "]
        guard let separator = separators.first(where: { needle.localizedCaseInsensitiveContains($0) }) else { return [] }

        let parts = needle.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count == 2 else { return [] }

        let selectionsPerPart = parts.map { selections(for: $0, on: page) }
        guard selectionsPerPart.allSatisfy({ $0.count > occurrenceIndex }) else { return [] }

        return selectionsPerPart[0][occurrenceIndex].rects + selectionsPerPart[1][occurrenceIndex].rects
    }

    private func selections(for needle: String, on page: PDFPage) -> [(rects: [CGRect], anchor: CGRect)] {
        guard let doc = page.document, !needle.isEmpty else { return [] }
        return doc.findString(needle, withOptions: [.caseInsensitive])
            .compactMap { selection in
                let rects = perLineRects(of: selection, on: page)
                guard !rects.isEmpty else { return nil }
                let anchor = rects.reduce(.null) { partial, rect in
                    partial.isNull ? rect : partial.union(rect)
                }
                return (rects, anchor)
            }
            .sorted { lhs, rhs in
                if abs(lhs.anchor.minY - rhs.anchor.minY) > 8 {
                    return lhs.anchor.minY > rhs.anchor.minY
                }
                return lhs.anchor.minX < rhs.anchor.minX
            }
    }

    private func rectsViaOCRFallback(for spans: [DetectedSpan], on page: PDFPage) async -> [(CGRect, DetectedSpan)] {
        guard let ocrPage = await ocrText(for: page), !ocrPage.combinedText.isEmpty else { return [] }
        let pageBounds = page.bounds(for: .mediaBox)
        let text = ocrPage.combinedText
        var results: [(CGRect, DetectedSpan)] = []
        for span in spans where !span.text.isEmpty {
            var searchStart = text.startIndex
            while let r = text.range(of: span.text, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                let s = text.distance(from: text.startIndex, to: r.lowerBound)
                let e = text.distance(from: text.startIndex, to: r.upperBound)
                for norm in ocrPage.normalizedBoxes(start: s, end: e) {
                    results.append((CGRect(
                        x: norm.minX * pageBounds.width,
                        y: norm.minY * pageBounds.height,
                        width: norm.width * pageBounds.width,
                        height: norm.height * pageBounds.height
                    ), span))
                }
                searchStart = r.upperBound
            }
        }
        return results
    }

    // MARK: - Blurred page snapshot (for editor preview)

    private func blurredImage(for page: PDFPage) -> CGImage? {
        if let cached = blurCache.object(forKey: page) { return cached }

        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let pixelWidth = Int(pageBounds.width * scale)
        let pixelHeight = Int(pageBounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        for ann in detached { page.removeAnnotation(ann) }
        defer { for ann in detached { page.addAnnotation(ann) } }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)

        guard let sharpCG = ctx.makeImage() else { return nil }
        guard let blurred = gaussianBlurred(sharpCG) else { return nil }

        blurCache.setObject(blurred, forKey: page)
        return blurred
    }

    private func gaussianBlurred(_ sharp: CGImage) -> CGImage? {
        let sharpCI = CIImage(cgImage: sharp)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = sharpCI
        blur.radius = Float(min(sharp.width, sharp.height)) * 0.02
        guard let blurredCI = blur.outputImage?.cropped(to: sharpCI.extent) else { return nil }
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        return ciContext.createCGImage(blurredCI, from: blurredCI.extent)
    }

    // MARK: - True (rasterized) save

    private func saveSecurely(to url: URL, options: ExportOptions) -> URL? {
        guard let doc = document else { return nil }
        let newDoc = PDFDocument()
        newDoc.documentAttributes = options.removeMetadata ? [:] : doc.documentAttributes

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let rectsForPage = redactionAnnotations
                .filter { $0.page === page }
                .map { $0.annotation.bounds }

            if rectsForPage.isEmpty && !options.removeMetadata {
                if let copy = page.copy() as? PDFPage {
                    newDoc.insert(copy, at: newDoc.pageCount)
                }
            } else {
                guard let baked = bakedPage(page, rects: rectsForPage, style: redactionStyle) else {
                    return nil
                }
                newDoc.insert(baked, at: newDoc.pageCount)
            }
        }

        return newDoc.write(to: url) ? url : nil
    }

    private func bakedPage(_ page: PDFPage, rects: [CGRect], style: RedactionStyle) -> PDFPage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let pixelWidth = Int(pageBounds.width * scale)
        let pixelHeight = Int(pageBounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        for ann in detached { page.removeAnnotation(ann) }
        defer { for ann in detached { page.addAnnotation(ann) } }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        let pixelRects: [CGRect] = rects.map { r in
            CGRect(x: r.minX * scale, y: r.minY * scale,
                   width: r.width * scale, height: r.height * scale)
                .insetBy(dx: -2, dy: -2)
        }

        switch style {
        case .blackRectangle:
            ctx.setFillColor(NSColor.black.cgColor)
            for r in pixelRects { ctx.fill(r) }

        case .blur:
            guard let sharpCG = ctx.makeImage() else { return nil }
            guard let blurredCG = gaussianBlurred(sharpCG) else { return nil }

            for r in pixelRects {
                ctx.saveGState()
                ctx.clip(to: r)
                ctx.draw(blurredCG, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                ctx.restoreGState()
            }
        }

        guard let finalCG = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: finalCG, size: pageBounds.size)
        return PDFPage(image: image)
    }

    private func suggestedSaveName() -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "dokument"
        return "\(base)-geschwaerzt.pdf"
    }
}

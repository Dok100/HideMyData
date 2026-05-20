import Foundation
import PDFKit
import AppKit
internal import UniformTypeIdentifiers

@Observable
@MainActor
final class PDFRedactor {
    private enum SaveAttemptResult {
        case success(RedactionExportResult)
        case failure(String)
    }

    struct FocusTarget: Equatable {
        let pageIndex: Int
        let rect: CGRect
    }

    private struct RedactionEntry {
        let page: PDFPage
        let annotation: PDFAnnotation
        let findingID: UUID?
    }

    var phase: RedactionPhase = .empty
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
    var lastExportReport: ExportValidationReport?
    var detectionNotice: DocumentDetectionNotice?

    private var redactionAnnotations: [RedactionEntry] = []
    private var previewAnnotations: [RedactionEntry] = []
    private var dismissedPreviewAnnotations: [RedactionEntry] = []
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
    var manualRedactionCount: Int { redactionAnnotations.filter { $0.findingID == nil }.count }
    var hasReviewFindings: Bool { !reviewFindings.isEmpty }
    var pendingReviewCount: Int { reviewFindings.filter { $0.status == .pending }.count }
    var hasPendingReview: Bool { pendingReviewCount > 0 }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }

    // MARK: - Open / Save

    func presentOpenPanel() -> DocumentOpenResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard loadPDF(from: url) else {
            return .failed("Das PDF „\(url.lastPathComponent)“ konnte nicht geöffnet werden. Prüfe bitte, ob die Datei vollständig ist und wirklich ein lesbares PDF enthält.")
        }
        return .opened(url)
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
        lastExportReport = nil
        detectionNotice = nil
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
        lastExportReport = nil
        detectionNotice = nil
        self.document = doc
        self.sourceURL = originalURL
        self.pageCount = doc.pageCount
        self.currentPageIndex = 0
        self.requestedPageIndex = nil
        self.phase = .loaded
        return true
    }

    func save() -> DocumentSaveResult {
        guard document != nil else {
            return .failed("Es ist gerade kein PDF geladen, das gespeichert werden kann.")
        }
        let panel = NSSavePanel()
        let exportAccessory = ExportOptionsAccessoryView()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.title = "Geschützte Kopie speichern"
        panel.message = "Wähle Speicherort und Dateinamen für das geschützte PDF."
        panel.prompt = "Speichern"
        panel.nameFieldLabel = "Dateiname:"
        panel.showsTagField = false
        panel.nameFieldStringValue = PDFExportLifecycleSupport.suggestedSaveName(for: sourceURL)
        panel.accessoryView = exportAccessory
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        switch saveSecurely(to: url, options: exportAccessory.options) {
        case .success(let exportResult):
            lastExportReport = exportResult.report
            phase = .saved(exportResult.url)
            return .saved(exportResult.url)
        case .failure(let message):
            phase = .failed(message)
            return .failed(message)
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
        detectionNotice = nil
        phase = .detecting

        var totalSpans = 0
        var totalRects = 0
        var reviewCandidates: [ReviewFindingCandidate] = []
        var usedNativeText = false
        var usedOCRText = false
        var pagesWithoutUsableText = 0

        for pageIndex in 0..<doc.pageCount {
            if Task.isCancelled { return }
            guard let page = doc.page(at: pageIndex) else { continue }

            let pageText = page.string ?? ""
            let ocrPage = await ocrText(for: page)
            guard let detectionInput = PDFDetectionLifecycleSupport.pageDetectionInput(
                pageText: pageText,
                ocrPage: ocrPage
            ) else {
                pagesWithoutUsableText += 1
                continue
            }
            let source = detectionInput.source
            let modelInput = detectionInput.modelInput
            let offsetMap = detectionInput.offsetMap
            usedNativeText = usedNativeText || detectionInput.usedNativeText
            usedOCRText = usedOCRText || detectionInput.usedOCRText

            let result = await detector.detect(modelInput)
            if Task.isCancelled { return }
            switch result {
            case .failure(let err):
                phase = .failed("Erkennungsfehler auf Seite \(pageIndex + 1): \(err.localizedDescription)")
                return
            case .success(let spans):
                let supplementalContextSpans = contextualSupplementalSpans(in: source.text)
                let ocrSupplemental = source.ocrPage.map { supplementalOCRContextSpans(in: $0) } ?? ([], [])
                let pageResult = await PDFDetectionReviewSupport.resolvePageDetections(
                    spans: spans,
                    source: source,
                    page: page,
                    offsetMap: offsetMap,
                    contextualSupplementalSpans: supplementalContextSpans,
                    ocrSupplemental: ocrSupplemental,
                    suppressHeaderLikeFinding: { span, pageText in
                        self.shouldSuppressHeaderLikeFinding(span, in: pageText)
                    },
                    boundingRects: { span, source, page in
                        self.boundingRects(for: span, source: source, on: page)
                    },
                    rectsViaOCRFallback: { spans, page in
                        await self.rectsViaOCRFallback(for: spans, on: page)
                    }
                )
                debugEntries.append(
                    DetectionDebugEntry(
                        title: "Seite \(pageIndex + 1)",
                        textSourceLabel: source.debugLabel,
                        rawText: source.text,
                        normalizedText: modelInput,
                        findings: pageResult.visibleDebugSpans,
                        diagnostics: PIIDetector.visiblePatternDiagnostics(for: modelInput),
                        previewDiagnostics: pageResult.previewDiagnostics
                    )
                )
                totalSpans += pageResult.visibleDebugSpans.count
                reviewCandidates.append(
                    contentsOf: pageResult.reviewCandidates.map { candidate in
                        ReviewFindingCandidate(
                            category: candidate.category,
                            snippet: candidate.snippet,
                            source: candidate.source,
                            confidence: candidate.confidence,
                            pageIndex: pageIndex,
                            rects: candidate.rects
                        )
                    }
                )
                totalRects += pageResult.totalRects
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
        detectionNotice = PDFDetectionLifecycleSupport.completionNotice(
            reviewFindingsEmpty: reviewFindings.isEmpty,
            totalSpans: totalSpans,
            usedNativeText: usedNativeText,
            usedOCRText: usedOCRText,
            pagesWithoutUsableText: pagesWithoutUsableText
        )
        phase = .redacted(spanCount: totalSpans, rectCount: totalRects)
    }

    private func ocrText(for page: PDFPage) async -> OCRPage? {
        guard let cg = renderPageToCGImage(page, scale: 2) else { return nil }
        return try? await OCREngine.recognize(cg)
    }

    private func shouldSuppressHeaderLikeFinding(_ span: DetectedSpan, in pageText: String) -> Bool {
        PDFHeaderSuppressionSupport.shouldSuppressHeaderLikeFinding(span, in: pageText)
    }

    private func contextualSupplementalSpans(in text: String) -> [DetectedSpan] {
        NativePDFContextAnalyzer.contextualSupplementalSpans(in: text)
    }

    private func supplementalOCRContextSpans(in page: OCRPage) -> ([DetectedSpan], [String]) {
        PDFOCRSupplementalAnalyzer.analyze(page: page)
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
    private func addPreview(rect: CGRect, on page: PDFPage, findingID: UUID, rectIsPreNormalized: Bool = false) -> PDFAnnotation {
        let padded = rectIsPreNormalized ? rect : normalizedDisplayRect(for: rect, on: page)
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

    func findingID(at point: CGPoint, on page: PDFPage) -> UUID? {
        let match = (redactionAnnotations + previewAnnotations)
            .filter { $0.page === page && $0.annotation.bounds.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.annotation.bounds.width * lhs.annotation.bounds.height
                let rhsArea = rhs.annotation.bounds.width * rhs.annotation.bounds.height
                if lhsArea == rhsArea {
                    return lhs.annotation.bounds.midY > rhs.annotation.bounds.midY
                }
                return lhsArea < rhsArea
            }
        return match?.findingID
    }

    func acceptFinding(_ id: UUID) {
        promotePreviewToRedaction(for: id)
        dismissedPreviewAnnotations.removeAll { $0.findingID == id }
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
        dismissPreviews(for: id)
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

    func reopenFinding(_ id: UUID) {
        guard let finding = reviewFindings.first(where: { $0.id == id }) else { return }

        switch finding.status {
        case .pending:
            selectFinding(id)
        case .accepted:
            restoreAcceptedFindingToPending(id)
        case .rejected:
            restoreDismissedPreviews(for: id)
            updateFinding(id) { $0.status = .pending }
            selectFinding(id)
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
        dismissedPreviewAnnotations.removeAll()
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
        dismissedPreviewAnnotations.removeAll()
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

    private func dismissPreviews(for findingID: UUID) {
        let matching = previewAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        previewAnnotations.removeAll { $0.findingID == findingID }
        dismissedPreviewAnnotations.append(contentsOf: matching)
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

    private func restoreDismissedPreviews(for findingID: UUID) {
        let matches = dismissedPreviewAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }
        dismissedPreviewAnnotations.removeAll { $0.findingID == findingID }
        for entry in matches {
            entry.page.addAnnotation(entry.annotation)
        }
        previewAnnotations.append(contentsOf: matches)
    }

    private func restoreAcceptedFindingToPending(_ findingID: UUID) {
        let matches = redactionAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }

        removeRedactions(for: findingID)
        for entry in matches {
            _ = addPreview(rect: entry.annotation.bounds, on: entry.page, findingID: findingID, rectIsPreNormalized: true)
        }
        updateFinding(findingID) { $0.status = .pending }
        selectFinding(findingID)
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
        FindingVisualSemantics.nsColor(for: category)
    }

    // MARK: - Bounding rects via character offsets (with text-search fallback)

    private func boundingRects(for span: DetectedSpan, source: PDFPageTextSource, on page: PDFPage) -> [CGRect] {
        switch source {
        case .nativeText(let pageText):
            if span.start >= 0,
               span.end > span.start,
               let utf16Range = nsRange(start: span.start, end: span.end, in: pageText),
               let selection = page.selection(for: utf16Range) {
                let rects = PDFTextRectResolver.perLineRects(of: selection, on: page)
                if !rects.isEmpty { return rects }
            }
            let occurrence = PDFTextRectResolver.occurrenceIndex(of: span.text, in: pageText, start: span.start)
            let textSearchRects = PDFTextRectResolver.rectsByTextSearch(
                needle: span.text,
                occurrenceIndex: occurrence,
                on: page
            )
            if !textSearchRects.isEmpty { return textSearchRects }

            if span.category == "private_person",
               span.text.localizedCaseInsensitiveContains(" und "),
               let occurrenceIndex = occurrence {
                let fallbackRects = PDFTextRectResolver.rectsByConjoinedNameSearch(
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

        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        guard let sharpCG = RedactionRendering.renderPDFPageSnapshot(page, detaching: detached),
              let blurred = RedactionRendering.gaussianBlurred(sharpCG) else { return nil }

        blurCache.setObject(blurred, forKey: page)
        return blurred
    }

    // MARK: - True (rasterized) save

    private func saveSecurely(to url: URL, options: ExportOptions) -> SaveAttemptResult {
        guard let doc = document else {
            return .failure("Es ist gerade kein PDF geladen, das gespeichert werden kann.")
        }
        let exportResult = PDFExportLifecycleSupport.saveRedactedCopy(
            sourceDocument: doc,
            destinationURL: url,
            options: options,
            redactionStyle: redactionStyle,
            manualRedactionCount: manualRedactionCount,
            detectionNotice: detectionNotice,
            rectsForPage: { page in
                redactionAnnotations
                    .filter { $0.page === page }
                    .map { $0.annotation.bounds }
            },
            detachableAnnotationsForPage: { page in
                redactionAnnotations
                    .filter { $0.page === page }
                    .map { $0.annotation }
            }
        )

        switch exportResult {
        case .success(let result):
            return .success(result)
        case .failure(let message):
            return .failure(message)
        }
    }
}

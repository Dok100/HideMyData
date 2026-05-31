import Foundation
import PDFKit
import AppKit

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

    struct RedactionEntry {
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
        PDFDocumentLifecycleSupport.presentOpenPanel { url in
            loadPDF(from: url)
        }
    }

    @discardableResult
    func loadPDF(from url: URL) -> Bool {
        switch PDFDocumentLifecycleSupport.loadDocument(from: url) {
        case .success(let loaded):
            installLoadedDocument(loaded)
            return true
        case .failure(let message):
            phase = .failed(message)
            return false
        }
    }

    private func installLoadedDocument(_ loaded: PDFDocumentLifecycleSupport.LoadedDocument) {
        cancelDetection()
        clearAllVisuals(silently: true)
        blurCache.removeAllObjects()
        clearReviewState()
        lastExportReport = nil
        detectionNotice = nil
        self.document = loaded.document
        self.sourceURL = loaded.sourceURL
        self.pageCount = loaded.pageCount
        self.currentPageIndex = 0
        self.requestedPageIndex = nil
        self.phase = .loaded
    }

    /// Load a PDF whose bytes are already in memory. Used by the recents flow so the
    /// security-scoped resource can be released as soon as the file is read, while
    /// `sourceURL` still points at the original location for save-name suggestions.
    @discardableResult
    func loadPDF(data: Data, originalURL: URL) -> Bool {
        switch PDFDocumentLifecycleSupport.loadDocument(data: data, originalURL: originalURL) {
        case .success(let loaded):
            installLoadedDocument(loaded)
            return true
        case .failure(let message):
            phase = .failed(message)
            return false
        }
    }

    func save() -> DocumentSaveResult {
        guard document != nil else {
            return .failed("Es ist gerade kein PDF geladen, das gespeichert werden kann.")
        }
        let (panel, exportAccessory) = PDFDocumentLifecycleSupport.makeSavePanel(sourceURL: sourceURL)
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
                        PDFBoundingRectSupport.boundingRects(for: span, source: source, on: page)
                    },
                    rectsViaOCRFallback: { spans, page in
                        await PDFBoundingRectSupport.rectsViaOCRFallback(
                            for: spans,
                            on: page,
                            ocrPageProvider: { page in await self.ocrText(for: page) }
                        )
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
        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        guard let cg = PDFPageRenderSupport.renderPageToCGImage(page, scale: 2, detaching: detached) else { return nil }
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
        let ann = PDFAnnotationMutationSupport.addRedaction(
            rect: rect,
            on: page,
            findingID: findingID,
            rectIsPreNormalized: rectIsPreNormalized,
            redactionStyle: redactionStyle,
            blurredImage: redactionStyle == .blur ? blurredImage(for: page) : nil,
            redactionAnnotations: &redactionAnnotations
        )

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
        PDFAnnotationMutationSupport.addPreview(
            rect: rect,
            on: page,
            findingID: findingID,
            category: reviewFindings.first(where: { $0.id == findingID })?.category,
            rectIsPreNormalized: rectIsPreNormalized,
            redactionStyle: redactionStyle,
            previewAnnotations: &previewAnnotations
        )
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
        PDFAnnotationReviewLifecycleSupport.isRedaction(
            ann,
            redactionAnnotations: redactionAnnotations
        )
    }

    func findingID(at point: CGPoint, on page: PDFPage) -> UUID? {
        PDFAnnotationReviewLifecycleSupport.findingID(
            at: point,
            on: page,
            redactionAnnotations: redactionAnnotations,
            previewAnnotations: previewAnnotations
        )
    }

    func acceptFinding(_ id: UUID) {
        promotePreviewToRedaction(for: id)
        dismissedPreviewAnnotations.removeAll { $0.findingID == id }
        updateFinding(id) { $0.status = .accepted }
        selectFinding(id)
    }

    func acceptAllFindings() {
        for id in PDFAnnotationReviewLifecycleSupport.pendingFindingIDs(reviewFindings: reviewFindings) {
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
        PDFAnnotationReviewLifecycleSupport.selectFinding(
            id,
            document: document,
            previewAnnotations: previewAnnotations,
            redactionAnnotations: redactionAnnotations,
            focusedFindingID: &focusedFindingID,
            focusTarget: &focusTarget,
            currentPageIndex: &currentPageIndex,
            focusRequestID: &focusRequestID
        )
    }

    func goToPreviousPage() {
        PDFAnnotationReviewLifecycleSupport.goToPage(
            currentPageIndex - 1,
            pageCount: pageCount,
            currentPageIndex: &currentPageIndex,
            requestedPageIndex: &requestedPageIndex,
            pageNavigationRequest: &pageNavigationRequest
        )
    }

    func goToNextPage() {
        PDFAnnotationReviewLifecycleSupport.goToPage(
            currentPageIndex + 1,
            pageCount: pageCount,
            currentPageIndex: &currentPageIndex,
            requestedPageIndex: &requestedPageIndex,
            pageNavigationRequest: &pageNavigationRequest
        )
    }

    func goToPage(_ pageIndex: Int) {
        PDFAnnotationReviewLifecycleSupport.goToPage(
            pageIndex,
            pageCount: pageCount,
            currentPageIndex: &currentPageIndex,
            requestedPageIndex: &requestedPageIndex,
            pageNavigationRequest: &pageNavigationRequest
        )
    }

    func updateVisiblePage(index: Int) {
        PDFAnnotationReviewLifecycleSupport.updateVisiblePage(
            index: index,
            currentPageIndex: &currentPageIndex
        )
    }

    func clearRedactions() {
        cancelDetection()
        clearAllVisuals(silently: false)
        clearReviewState()
    }

    private func clearAllVisuals(silently: Bool) {
        PDFAnnotationReviewLifecycleSupport.clearAllVisuals(
            redactionAnnotations: &redactionAnnotations,
            previewAnnotations: &previewAnnotations,
            dismissedPreviewAnnotations: &dismissedPreviewAnnotations
        )
        if !silently, document != nil { phase = .loaded }
    }

    private func restyleAllAnnotations() {
        let priorPhase = phase
        let snapshot = redactionAnnotations
        PDFAnnotationMutationSupport.rebuildRedactions(
            from: snapshot,
            redactionStyle: redactionStyle,
            blurredImageProvider: { page in blurredImage(for: page) },
            redactionAnnotations: &redactionAnnotations
        )
        phase = priorPhase
    }

    private func clearReviewState() {
        pageCount = document?.pageCount ?? 0
        PDFAnnotationReviewLifecycleSupport.clearReviewState(
            reviewFindings: &reviewFindings,
            focusedFindingID: &focusedFindingID,
            focusTarget: &focusTarget,
            currentPageIndex: &currentPageIndex,
            requestedPageIndex: &requestedPageIndex,
            debugEntries: &debugEntries,
            dismissedPreviewAnnotations: &dismissedPreviewAnnotations
        )
    }

    private func dismissPreviews(for findingID: UUID) {
        PDFAnnotationReviewLifecycleSupport.dismissPreviews(
            for: findingID,
            previewAnnotations: &previewAnnotations,
            dismissedPreviewAnnotations: &dismissedPreviewAnnotations
        )
    }

    private func promotePreviewToRedaction(for findingID: UUID) {
        let matches = PDFAnnotationReviewLifecycleSupport.promotePreviewToRedaction(
            findingID: findingID,
            previewAnnotations: &previewAnnotations
        )
        guard !matches.isEmpty else { return }
        for entry in matches {
            let page = entry.page
            let rect = entry.annotation.bounds
            addRedaction(rect: rect, on: page, source: .auto, findingID: findingID, rectIsPreNormalized: true)
        }
    }

    private func restoreDismissedPreviews(for findingID: UUID) {
        PDFAnnotationReviewLifecycleSupport.restoreDismissedPreviews(
            for: findingID,
            previewAnnotations: &previewAnnotations,
            dismissedPreviewAnnotations: &dismissedPreviewAnnotations
        )
    }

    private func restoreAcceptedFindingToPending(_ findingID: UUID) {
        let matches = PDFAnnotationReviewLifecycleSupport.reopenAcceptedFinding(
            findingID,
            redactionAnnotations: &redactionAnnotations
        )
        guard !matches.isEmpty else { return }
        for entry in matches {
            _ = addPreview(rect: entry.annotation.bounds, on: entry.page, findingID: findingID, rectIsPreNormalized: true)
        }
        updateFinding(findingID) { $0.status = .pending }
        selectFinding(findingID)
    }

    private func syncFindingStateAfterRedactionRemoval(findingID: UUID) {
        PDFAnnotationReviewLifecycleSupport.syncFindingStateAfterRedactionRemoval(
            findingID: findingID,
            redactionAnnotations: redactionAnnotations,
            reviewFindings: &reviewFindings
        )
    }

    private func updateFinding(_ id: UUID, mutate: (inout ReviewFinding) -> Void) {
        PDFAnnotationReviewLifecycleSupport.updateFinding(
            id,
            reviewFindings: &reviewFindings,
            mutate: mutate
        )
    }

    // MARK: - Blurred page snapshot (for editor preview)

    private func blurredImage(for page: PDFPage) -> CGImage? {
        let detached = redactionAnnotations.filter { $0.page === page }.map { $0.annotation }
        return PDFPageRenderSupport.blurredImage(for: page, using: blurCache, detaching: detached)
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

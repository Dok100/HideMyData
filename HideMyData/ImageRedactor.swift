import Foundation
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
internal import UniformTypeIdentifiers

@Observable
@MainActor
final class ImageRedactor {
    private enum SaveAttemptResult {
        case success(RedactionExportResult)
        case failure(String)
    }

    struct RedactionEntry {
        let rect: CGRect
        let findingID: UUID?
    }

    var phase: RedactionPhase = .empty
    var image: CGImage?
    var sourceURL: URL?
    var sourceUTI: UTType?
    var redactionStyle: RedactionStyle = .blackRectangle
    var editingMode: EditingMode = .view
    var reviewFindings: [ReviewFinding] = []
    var focusedFindingID: UUID?
    var debugEntries: [DetectionDebugEntry] = []
    var lastExportReport: ExportValidationReport?
    var detectionNotice: DocumentDetectionNotice?

    private var sourceImageProperties: [CFString: Any]?
    private var detectionTask: Task<Void, Never>?
    private var redactionEntries: [RedactionEntry] = []
    private var previewEntries: [RedactionEntry] = []
    private var dismissedPreviewEntries: [RedactionEntry] = []

    var statusText: String {
        switch phase {
        case .empty: return "Kein Bild"
        case .loaded:
            if redactionRects.isEmpty && previewRects.isEmpty { return "Geladen" }
            if !previewRects.isEmpty { return "\(previewRects.count) Markierung\(previewRects.count == 1 ? "" : "en")" }
            return "\(redactionRects.count) Schwärzung\(redactionRects.count == 1 ? "" : "en")"
        case .detecting: return "PII wird erkannt…"
        case .redacted(_, let r):
            return "\(r) Bereich\(r == 1 ? "" : "e") vorbereitet"
        case .saved(let url): return "Gespeichert → \(url.lastPathComponent)"
        case .failed(let m): return "Fehler: \(m)"
        }
    }

    var hasRedactions: Bool { !redactionRects.isEmpty }
    var canDetect: Bool { image != nil && phase != .detecting }
    var redactionCount: Int { redactionEntries.count }
    var manualRedactionCount: Int { redactionEntries.filter { $0.findingID == nil }.count }
    var hasReviewFindings: Bool { !reviewFindings.isEmpty }
    var pendingReviewCount: Int { reviewFindings.filter { $0.status == .pending }.count }
    var hasPendingReview: Bool { pendingReviewCount > 0 }

    var pixelSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    var redactionRects: [CGRect] {
        redactionEntries.map(\.rect)
    }

    var previewRects: [CGRect] {
        previewEntries.map(\.rect)
    }

    var previewRectEntries: [(rect: CGRect, findingID: UUID?)] {
        previewEntries.map { ($0.rect, $0.findingID) }
    }

    // MARK: - Open / Save

    func presentOpenPanel() -> DocumentOpenResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard loadImage(from: url) else {
            return .failed("Das Bild „\(url.lastPathComponent)“ konnte nicht geöffnet werden. Prüfe bitte, ob die Datei vollständig ist und ein unterstütztes Bildformat hat.")
        }
        return .opened(url)
    }

    @discardableResult
    func loadImage(from url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = normalizedCGImage(from: src) else {
            phase = .failed("Bild konnte nicht geöffnet werden: \(url.lastPathComponent)")
            return false
        }
        let utiString = CGImageSourceGetType(src) as String? ?? ""
        let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        ingest(cg: cg, sourceURL: url, uti: UTType(utiString) ?? .png, properties: properties)
        return true
    }

    @discardableResult
    func loadImage(data: Data, originalURL: URL) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = normalizedCGImage(from: src) else {
            phase = .failed("Bild konnte nicht geöffnet werden: \(originalURL.lastPathComponent)")
            return false
        }
        let utiString = CGImageSourceGetType(src) as String? ?? ""
        let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        ingest(cg: cg, sourceURL: originalURL, uti: UTType(utiString) ?? .png, properties: properties)
        return true
    }

    private func normalizedCGImage(from source: CGImageSource) -> CGImage? {
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard raw != 1, let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return cg
        }
        let ci = CIImage(cgImage: cg).oriented(orientation)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ci, from: ci.extent)
    }

    private func ingest(cg: CGImage, sourceURL: URL, uti: UTType, properties: [CFString: Any]?) {
        cancelDetection()
        self.image = cg
        self.sourceURL = sourceURL
        self.sourceUTI = uti
        self.sourceImageProperties = properties
        self.lastExportReport = nil
        self.detectionNotice = nil
        self.redactionEntries = []
        self.previewEntries = []
        clearReviewState()
        self.phase = .loaded
    }

    func save() -> DocumentSaveResult {
        guard image != nil else {
            return .failed("Es ist gerade kein Bild geladen, das gespeichert werden kann.")
        }
        let outUTI = sourceUTI ?? .png
        let panel = NSSavePanel()
        let exportAccessory = ExportOptionsAccessoryView()
        panel.allowedContentTypes = [outUTI]
        panel.canCreateDirectories = true
        panel.title = "Geschützte Kopie speichern"
        panel.message = "Wähle Speicherort und Dateinamen für das geschützte Bild."
        panel.prompt = "Speichern"
        panel.nameFieldLabel = "Dateiname:"
        panel.showsTagField = false
        panel.nameFieldStringValue = ImageExportLifecycleSupport.suggestedSaveName(sourceURL: sourceURL, uti: outUTI)
        panel.accessoryView = exportAccessory
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        switch writeRedacted(to: url, uti: outUTI, options: exportAccessory.options) {
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
        guard let cg = image else { return }
        redactionEntries.removeAll()
        previewEntries.removeAll()
        clearReviewState()
        detectionNotice = nil
        phase = .detecting

        let preparation = ImageDetectionLifecycleSupport.prepareOCRResult(try? await OCREngine.recognize(cg))
        if Task.isCancelled { return }
        switch preparation {
        case .failed(let message):
            phase = .failed(message)
            return
        case .noUsableText(let notice):
            detectionNotice = notice
            phase = .redacted(spanCount: 0, rectCount: 0)
            return
        case .success(let prepared):
            let ocr = prepared.ocrPage
            let modelInput = prepared.modelInput

            let result = await detector.detect(modelInput)
            if Task.isCancelled { return }
            switch result {
            case .failure(let err):
                phase = .failed("Erkennungsfehler: \(err.localizedDescription)")
            case .success(let spans):
                let supplementalAnalysis = supplementalOCRContextAnalysis(in: ocr, modelInput: modelInput)
                let resolved = ImageDetectionLifecycleSupport.resolveDetection(
                    spans: spans,
                    prepared: prepared,
                    supplementalAnalysis: supplementalAnalysis,
                    pixelRectFromNormalized: pixelRect(fromNormalized:)
                )
                let reviewProjections = ReviewFindingCompactor.compact(resolved.reviewCandidates)
                for projection in reviewProjections {
                    reviewFindings.append(projection.finding)
                    for rect in projection.rects {
                        addPreview(rect: rect, findingID: projection.finding.id)
                    }
                }
                restoreMissingSupplementalCandidates(resolved.supplementalCandidates)
                restoreMissingWindowRecipientPrelude(in: ocr)
                let previewDiagnostics = makePreviewDiagnostics(in: ocr)
                debugEntries = [
                    ImageDetectionLifecycleSupport.debugEntry(
                        ocrPage: ocr,
                        modelInput: modelInput,
                        findings: resolved.visibleDebugSpans,
                        diagnostics: resolved.baseDiagnostics,
                        previewDiagnostics: previewDiagnostics
                    )
                ]
                if let firstPending = reviewFindings.first(where: { $0.status == .pending }) {
                    selectFinding(firstPending.id)
                }
                detectionNotice = ImageDetectionLifecycleSupport.weakOCRNoticeIfNeeded(
                    reviewFindings: reviewFindings,
                    modelSpans: spans,
                    ocrText: ocr.combinedText
                )
                phase = .redacted(spanCount: spans.count, rectCount: previewRects.count)
            }
        }
    }

    private func supplementalOCRContextAnalysis(in page: OCRPage, modelInput: String) -> (candidates: [ImageSupplementalOCRCandidate], diagnostics: [String]) {
        ImageOCRSupplementalAnalyzer.analyze(page: page, modelInput: modelInput)
    }

    private func restoreMissingSupplementalCandidates(_ candidates: [ImageSupplementalOCRCandidate]) {
        let recoveries = ImageReviewRecoverySupport.missingSupplementalRecoveries(
            candidates: candidates,
            pixelRectFromNormalized: pixelRect(fromNormalized:),
            isRectMostlyVisible: isRectMostlyVisible(_:)
        )

        for recovery in recoveries {
            reviewFindings.append(recovery.finding)
            for rect in recovery.rects {
                addPreview(rect: rect, findingID: recovery.finding.id)
            }
        }
    }

    private func restoreMissingWindowRecipientPrelude(in page: OCRPage) {
        let recoveries = ImageReviewRecoverySupport.windowRecipientPreludeRecoveries(
            page: page,
            pixelRectFromNormalized: pixelRect(fromNormalized:),
            isRectMostlyVisible: isRectMostlyVisible(_:)
        )

        for recovery in recoveries {
            reviewFindings.append(recovery.finding)
            for rect in recovery.rects {
                addPreview(rect: rect, findingID: recovery.finding.id)
            }
        }
    }

    private func isRectMostlyVisible(_ rect: CGRect) -> Bool {
        ImageReviewRecoverySupport.isRectMostlyVisible(
            rect,
            existingPreviewRects: previewEntries.map(\.rect)
        )
    }

    private func makePreviewDiagnostics(in page: OCRPage) -> [String] {
        ImagePreviewDiagnosticsSupport.lines(
            for: reviewFindings,
            previewRectEntries: previewRectEntries,
            page: page,
            pixelRectFromNormalized: pixelRect(fromNormalized:)
        )
    }

    func clearRedactions() {
        cancelDetection()
        ImageAnnotationReviewLifecycleSupport.clearRedactions(
            redactionEntries: &redactionEntries,
            previewEntries: &previewEntries,
            dismissedPreviewEntries: &dismissedPreviewEntries
        )
        clearReviewState()
        if image != nil { phase = .loaded }
    }

    func addRedaction(rect: CGRect, findingID: UUID? = nil, rectIsPreNormalized: Bool = false) {
        let finalRect = rectIsPreNormalized ? rect : harmonizedDisplayRect(for: rect)
        redactionEntries.append(RedactionEntry(rect: finalRect, findingID: findingID))
        switch phase {
        case .loaded, .redacted:
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count)
        default:
            break
        }
    }

    private func addPreview(rect: CGRect, findingID: UUID) {
        previewEntries.append(RedactionEntry(rect: harmonizedDisplayRect(for: rect), findingID: findingID))
        if case .loaded = phase {
            phase = .redacted(spanCount: 0, rectCount: previewRects.count)
        }
    }

    func removeRedaction(at index: Int) {
        guard redactionEntries.indices.contains(index) else { return }
        let removed = redactionEntries.remove(at: index)
        if let findingID = removed.findingID {
            syncFindingStateAfterRedactionRemoval(findingID: findingID)
        }
        if redactionRects.isEmpty, image != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count)
        }
    }

    func acceptFinding(_ id: UUID) {
        promotePreviewToRedaction(for: id)
        dismissedPreviewEntries.removeAll { $0.findingID == id }
        updateFinding(id) { $0.status = .accepted }
        focusedFindingID = id
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
        ImageAnnotationReviewLifecycleSupport.rejectFinding(
            id,
            previewEntries: &previewEntries,
            dismissedPreviewEntries: &dismissedPreviewEntries
        )
        updateFinding(id) { $0.status = .rejected }
        if focusedFindingID == id { focusedFindingID = nil }
        if redactionRects.isEmpty && previewRects.isEmpty, image != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        }
    }

    func reopenFinding(_ id: UUID) {
        guard let finding = reviewFindings.first(where: { $0.id == id }) else { return }

        switch finding.status {
        case .pending:
            focusedFindingID = id
        case .accepted:
            guard ImageAnnotationReviewLifecycleSupport.reopenAcceptedFinding(
                id,
                redactionEntries: &redactionEntries,
                previewEntries: &previewEntries
            ) else { return }
            updateFinding(id) { $0.status = .pending }
            focusedFindingID = id
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        case .rejected:
            guard ImageAnnotationReviewLifecycleSupport.reopenRejectedFinding(
                id,
                previewEntries: &previewEntries,
                dismissedPreviewEntries: &dismissedPreviewEntries
            ) else { return }
            updateFinding(id) { $0.status = .pending }
            focusedFindingID = id
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        }
    }

    func selectFinding(_ id: UUID) {
        focusedFindingID = id
    }

    func findingID(at point: CGPoint) -> UUID? {
        let match = (redactionEntries + previewEntries)
            .filter { $0.rect.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                if lhsArea == rhsArea {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhsArea < rhsArea
            }
        return match?.findingID
    }

    // MARK: - Helpers

    private func pixelRect(fromNormalized norm: CGRect) -> CGRect {
        let w = CGFloat(image?.width ?? 0)
        let h = CGFloat(image?.height ?? 0)
        let x = norm.minX * w
        let y = (1 - norm.maxY) * h
        return CGRect(x: x, y: y, width: norm.width * w, height: norm.height * h)
    }

    private func harmonizedDisplayRect(for rect: CGRect) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: pixelSize)
        let workingRect = rect.standardized
        guard redactionStyle == .blackRectangle else {
            return workingRect.insetBy(dx: -1, dy: -1).intersection(imageBounds)
        }

        let targetHeight = max(12, round(workingRect.height + 4))
        let adjusted = CGRect(
            x: workingRect.minX - 1,
            y: workingRect.midY - (targetHeight / 2),
            width: workingRect.width + 2,
            height: targetHeight
        )
        return adjusted.intersection(imageBounds)
    }

    private func writeRedacted(to url: URL, uti: UTType, options: ExportOptions) -> SaveAttemptResult {
        guard let cg = image else {
            return .failure("Es ist gerade kein Bild geladen, das exportiert werden kann.")
        }
        switch ImageExportLifecycleSupport.writeRedactedImage(
            sourceImage: cg,
            destinationURL: url,
            uti: uti,
            options: options,
            redactionRects: redactionRects,
            redactionStyle: redactionStyle,
            sourceImageProperties: sourceImageProperties,
            manualRedactionCount: manualRedactionCount,
            detectionNotice: detectionNotice
        ) {
        case .success(let result):
            return .success(result)
        case .failure(let message):
            return .failure(message)
        }
    }

    func findingRects(for findingID: UUID) -> [CGRect] {
        (previewEntries + redactionEntries)
            .filter { $0.findingID == findingID }
            .map(\.rect)
    }

    func findingColor(for findingID: UUID?) -> NSColor {
        guard let findingID,
              let finding = reviewFindings.first(where: { $0.id == findingID })
        else {
            return FindingVisualSemantics.nsColor(for: "custom_identifier")
        }
        return FindingVisualSemantics.nsColor(for: finding.category)
    }

    private func clearReviewState() {
        ImageAnnotationReviewLifecycleSupport.clearReviewState(
            reviewFindings: &reviewFindings,
            focusedFindingID: &focusedFindingID,
            debugEntries: &debugEntries,
            dismissedPreviewEntries: &dismissedPreviewEntries
        )
    }

    private func promotePreviewToRedaction(for findingID: UUID) {
        let rects = ImageAnnotationReviewLifecycleSupport.promotePreviewToRedaction(
            findingID: findingID,
            previewEntries: &previewEntries
        )
        guard !rects.isEmpty else { return }
        for rect in rects {
            addRedaction(rect: rect, findingID: findingID, rectIsPreNormalized: true)
        }
    }

    private func syncFindingStateAfterRedactionRemoval(findingID: UUID) {
        ImageAnnotationReviewLifecycleSupport.syncFindingStateAfterRedactionRemoval(
            findingID: findingID,
            redactionEntries: redactionEntries,
            reviewFindings: &reviewFindings
        )
    }

    private func updateFinding(_ id: UUID, mutate: (inout ReviewFinding) -> Void) {
        ImageAnnotationReviewLifecycleSupport.updateFinding(
            id,
            reviewFindings: &reviewFindings,
            mutate: mutate
        )
    }
}

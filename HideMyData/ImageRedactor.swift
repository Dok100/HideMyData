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

    private struct RedactionEntry {
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
        panel.nameFieldStringValue = suggestedSaveName(uti: outUTI)
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

        guard let ocr = try? await OCREngine.recognize(cg) else {
            phase = .failed("OCR fehlgeschlagen")
            return
        }
        if Task.isCancelled { return }
        if ocr.combinedText.isEmpty {
            detectionNotice = DocumentDetectionNotice(
                title: "Kaum lesbarer Text im Bild",
                message: "Apple Vision konnte in diesem Bild praktisch keinen lesbaren Text erkennen. Prüfe bitte Schärfe, Kontrast und Ausschnitt oder versuche eine klarere Aufnahme."
            )
            phase = .redacted(spanCount: 0, rectCount: 0)
            return
        }

        let (modelInput, offsetMap) = OCRNormalizer.normalize(ocr.combinedText, mode: .ocr)
        let originalCount = ocr.combinedText.count

        let result = await detector.detect(modelInput)
        if Task.isCancelled { return }
        switch result {
        case .failure(let err):
            phase = .failed("Erkennungsfehler: \(err.localizedDescription)")
        case .success(let spans):
            let supplementalAnalysis = supplementalOCRContextAnalysis(in: ocr, modelInput: modelInput)
            let supplementalCandidates = supplementalAnalysis.candidates
            let supplementalSpans = supplementalCandidates.map(\.span)
            let visibleDebugSpans = (spans + supplementalSpans)
                .sorted {
                    if $0.start == $1.start { return $0.end < $1.end }
                    return $0.start < $1.start
                }
            let baseDiagnostics = PIIDetector.visiblePatternDiagnostics(for: modelInput) + supplementalAnalysis.diagnostics
            var reviewCandidates: [ReviewFindingCandidate] = []
            for span in visibleDebugSpans {
                if let supplementalCandidate = supplementalCandidates.first(where: {
                    $0.span.category == span.category &&
                    $0.span.start == span.start &&
                    $0.span.end == span.end &&
                    $0.span.text == span.text
                }) {
                    reviewCandidates.append(
                        ReviewFindingCandidate(
                            category: span.category,
                            snippet: span.text,
                            source: span.source,
                            confidence: span.confidence,
                            pageIndex: nil,
                            rects: supplementalCandidate.normalizedRects.map(pixelRect(fromNormalized:))
                        )
                    )
                    continue
                }

                let (origStart, origEnd) = OCRNormalizer.translateRange(
                    start: span.start, end: span.end, map: offsetMap, originalCount: originalCount
                )
                let normRects = ocr.normalizedBoxes(start: origStart, end: origEnd)
                guard !normRects.isEmpty else { continue }
                reviewCandidates.append(
                    ReviewFindingCandidate(
                        category: span.category,
                        snippet: span.text,
                        source: span.source,
                        confidence: span.confidence,
                        pageIndex: nil,
                        rects: normRects.map { pixelRect(fromNormalized: $0) }
                    )
                )
            }
            let reviewProjections = ReviewFindingCompactor.compact(reviewCandidates)
            for projection in reviewProjections {
                reviewFindings.append(projection.finding)
                for rect in projection.rects {
                    addPreview(rect: rect, findingID: projection.finding.id)
                }
            }
            restoreMissingSupplementalCandidates(supplementalCandidates)
            restoreMissingWindowRecipientPrelude(in: ocr)
            let previewDiagnostics = makePreviewDiagnostics(in: ocr)
            debugEntries = [
                DetectionDebugEntry(
                    title: "Bilddiagnose",
                    textSourceLabel: "Apple Vision OCR",
                    rawText: ocr.combinedText,
                    normalizedText: modelInput,
                    findings: visibleDebugSpans,
                    diagnostics: baseDiagnostics,
                    previewDiagnostics: previewDiagnostics
                )
            ]
            if let firstPending = reviewFindings.first(where: { $0.status == .pending }) {
                selectFinding(firstPending.id)
            }
            if reviewFindings.isEmpty && spans.isEmpty && DocumentTextHeuristics.lowSignalOCRText(ocr.combinedText) {
                detectionNotice = DocumentDetectionNotice(
                    title: "OCR-Ergebnis sehr schwach",
                    message: "Es wurde zwar etwas Text erkannt, aber nur sehr wenig verwertbarer Inhalt. Wenn sensible Daten sichtbar fehlen, versuche bitte ein klareres Bild."
                )
            }
            phase = .redacted(spanCount: spans.count, rectCount: previewRects.count)
        }
    }

    private func supplementalOCRContextAnalysis(in page: OCRPage, modelInput: String) -> (candidates: [ImageSupplementalOCRCandidate], diagnostics: [String]) {
        ImageOCRSupplementalAnalyzer.analyze(page: page, modelInput: modelInput)
    }

    private func restoreMissingSupplementalCandidates(_ candidates: [ImageSupplementalOCRCandidate]) {
        for candidate in candidates {
            let pixelRects = candidate.normalizedRects.map(pixelRect(fromNormalized:))
            let alreadyVisible = pixelRects.contains { rect in
                isRectMostlyVisible(rect)
            }
            guard !alreadyVisible else { continue }

            let finding = ReviewFinding(
                category: candidate.span.category,
                snippet: candidate.span.text,
                source: candidate.span.source,
                confidence: candidate.span.confidence,
                pageIndex: nil
            )
            reviewFindings.append(finding)
            for rect in pixelRects {
                addPreview(rect: rect, findingID: finding.id)
            }
        }
    }

    private func restoreMissingWindowRecipientPrelude(in page: OCRPage) {
        let recoveredCandidates = ImageOCRSupplementalAnalyzer.recoveredWindowRecipientPreludeCandidates(
            in: page,
            isNormalizedRectVisible: { normalizedRect in
                isRectMostlyVisible(pixelRect(fromNormalized: normalizedRect))
            }
        )

        for candidate in recoveredCandidates {
            for rect in candidate.normalizedRects.map(pixelRect(fromNormalized:)) {
                appendRecoveredPreview(span: candidate.span, rect: rect)
            }
        }
    }

    private func appendRecoveredPreview(span: DetectedSpan, rect: CGRect) {
        let finding = ReviewFinding(
            category: span.category,
            snippet: span.text,
            source: span.source,
            confidence: span.confidence,
            pageIndex: nil
        )
        reviewFindings.append(finding)
        addPreview(rect: rect, findingID: finding.id)
    }

    private func isRectMostlyVisible(_ rect: CGRect) -> Bool {
        previewEntries.contains { existing in
            let overlapRect = existing.rect.intersection(rect)
            guard !overlapRect.isNull else { return false }

            let candidateArea = max(rect.width * rect.height, 1)
            let overlapArea = overlapRect.width * overlapRect.height
            return overlapArea / candidateArea >= 0.6
        }
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
        redactionEntries.removeAll()
        previewEntries.removeAll()
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
        let matches = previewEntries.filter { $0.findingID == id }
        previewEntries.removeAll { $0.findingID == id }
        dismissedPreviewEntries.append(contentsOf: matches)
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
            let matches = redactionEntries.filter { $0.findingID == id }
            guard !matches.isEmpty else { return }
            redactionEntries.removeAll { $0.findingID == id }
            previewEntries.append(contentsOf: matches)
            updateFinding(id) { $0.status = .pending }
            focusedFindingID = id
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        case .rejected:
            let matches = dismissedPreviewEntries.filter { $0.findingID == id }
            guard !matches.isEmpty else { return }
            dismissedPreviewEntries.removeAll { $0.findingID == id }
            previewEntries.append(contentsOf: matches)
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
        guard let baked = RedactionRendering.bakeImageRedactions(
            into: cg,
            rects: redactionRects,
            style: redactionStyle
        ) else {
            return .failure("Das Bild konnte nicht exportiert werden, weil die Schwärzungen nicht sauber ins Bild eingebrannt werden konnten. Bitte versuche es erneut oder wähle einen anderen Speicherort.")
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti.identifier as CFString, 1, nil) else {
            return .failure("Für dieses Bildformat konnte kein Export-Ziel angelegt werden. Bitte versuche es erneut oder speichere als anderes Bildformat.")
        }
        CGImageDestinationAddImage(dest, baked, imageProperties(for: uti, options: options))
        guard CGImageDestinationFinalize(dest) else {
            return .failure("Das geschwärzte Bild konnte nicht am gewählten Ort gespeichert werden. Bitte prüfe Schreibrechte, freien Speicherplatz oder wähle einen anderen Speicherort.")
        }

        let report = ExportValidationReport(
            format: .image,
            redactionCount: redactionRects.count,
            manualRedactionCount: manualRedactionCount,
            redactedPageCount: nil,
            totalPageCount: nil,
            lowTextWarning: detectionNotice?.title.localizedCaseInsensitiveContains("lesbarer Text") == true
                || detectionNotice?.title.localizedCaseInsensitiveContains("OCR") == true,
            removedMetadata: options.removeMetadata,
            annotationsRemoved: true,
            bakedIntoPixels: !redactionRects.isEmpty
        )
        return .success(RedactionExportResult(url: url, report: report))
    }

    private func imageProperties(for uti: UTType, options: ExportOptions) -> CFDictionary? {
        var properties = options.removeMetadata ? [:] : sourceImageProperties ?? [:]
        properties[kCGImagePropertyOrientation] = 1

        if options.removeMetadata {
            if uti.conforms(to: .png) {
                properties[kCGImagePropertyPNGDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .jpeg) {
                properties[kCGImagePropertyJFIFDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .tiff) {
                properties[kCGImagePropertyTIFFDictionary] = [:] as CFDictionary
            }
        }

        return properties as CFDictionary
    }

    private func suggestedSaveName(uti: UTType) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "bild"
        let ext = uti.preferredFilenameExtension ?? "png"
        return "\(base)-geschwaerzt.\(ext)"
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
        reviewFindings.removeAll()
        focusedFindingID = nil
        debugEntries.removeAll()
        dismissedPreviewEntries.removeAll()
    }

    private func promotePreviewToRedaction(for findingID: UUID) {
        let matches = previewEntries.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }
        previewEntries.removeAll { $0.findingID == findingID }
        for entry in matches {
            addRedaction(rect: entry.rect, findingID: findingID, rectIsPreNormalized: true)
        }
    }

    private func syncFindingStateAfterRedactionRemoval(findingID: UUID) {
        guard !redactionEntries.contains(where: { $0.findingID == findingID }) else { return }
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
}

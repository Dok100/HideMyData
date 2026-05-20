import Foundation

struct ImageDetectionPreparedData {
    let ocrPage: OCRPage
    let modelInput: String
    let offsetMap: [Int]
    let originalCount: Int
}

enum ImageDetectionPreparationResult {
    case success(ImageDetectionPreparedData)
    case failed(String)
    case noUsableText(DocumentDetectionNotice)
}

struct ImageDetectionResolvedData {
    let visibleDebugSpans: [DetectedSpan]
    let baseDiagnostics: [String]
    let reviewCandidates: [ReviewFindingCandidate]
    let supplementalCandidates: [ImageSupplementalOCRCandidate]
}

enum ImageDetectionLifecycleSupport {
    static func prepareOCRResult(_ ocrPage: OCRPage?) -> ImageDetectionPreparationResult {
        guard let ocrPage else {
            return .failed("OCR fehlgeschlagen")
        }

        if ocrPage.combinedText.isEmpty {
            return .noUsableText(
                DocumentDetectionNotice(
                    title: "Kaum lesbarer Text im Bild",
                    message: "Apple Vision konnte in diesem Bild praktisch keinen lesbaren Text erkennen. Prüfe bitte Schärfe, Kontrast und Ausschnitt oder versuche eine klarere Aufnahme."
                )
            )
        }

        let (modelInput, offsetMap) = OCRNormalizer.normalize(ocrPage.combinedText, mode: .ocr)
        return .success(
            ImageDetectionPreparedData(
                ocrPage: ocrPage,
                modelInput: modelInput,
                offsetMap: offsetMap,
                originalCount: ocrPage.combinedText.count
            )
        )
    }

    static func resolveDetection(
        spans: [DetectedSpan],
        prepared: ImageDetectionPreparedData,
        supplementalAnalysis: (candidates: [ImageSupplementalOCRCandidate], diagnostics: [String]),
        pixelRectFromNormalized: (CGRect) -> CGRect
    ) -> ImageDetectionResolvedData {
        let supplementalCandidates = supplementalAnalysis.candidates
        let supplementalSpans = supplementalCandidates.map(\.span)
        let visibleDebugSpans = (spans + supplementalSpans)
            .sorted {
                if $0.start == $1.start { return $0.end < $1.end }
                return $0.start < $1.start
            }

        let baseDiagnostics = PIIDetector.visiblePatternDiagnostics(for: prepared.modelInput) + supplementalAnalysis.diagnostics

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
                        rects: supplementalCandidate.normalizedRects.map(pixelRectFromNormalized)
                    )
                )
                continue
            }

            let (origStart, origEnd) = OCRNormalizer.translateRange(
                start: span.start,
                end: span.end,
                map: prepared.offsetMap,
                originalCount: prepared.originalCount
            )
            let normRects = prepared.ocrPage.normalizedBoxes(start: origStart, end: origEnd)
            guard !normRects.isEmpty else { continue }
            reviewCandidates.append(
                ReviewFindingCandidate(
                    category: span.category,
                    snippet: span.text,
                    source: span.source,
                    confidence: span.confidence,
                    pageIndex: nil,
                    rects: normRects.map(pixelRectFromNormalized)
                )
            )
        }

        return ImageDetectionResolvedData(
            visibleDebugSpans: visibleDebugSpans,
            baseDiagnostics: baseDiagnostics,
            reviewCandidates: reviewCandidates,
            supplementalCandidates: supplementalCandidates
        )
    }

    static func weakOCRNoticeIfNeeded(
        reviewFindings: [ReviewFinding],
        modelSpans: [DetectedSpan],
        ocrText: String
    ) -> DocumentDetectionNotice? {
        guard reviewFindings.isEmpty,
              modelSpans.isEmpty,
              DocumentTextHeuristics.lowSignalOCRText(ocrText) else {
            return nil
        }

        return DocumentDetectionNotice(
            title: "OCR-Ergebnis sehr schwach",
            message: "Es wurde zwar etwas Text erkannt, aber nur sehr wenig verwertbarer Inhalt. Wenn sensible Daten sichtbar fehlen, versuche bitte ein klareres Bild."
        )
    }

    static func debugEntry(
        ocrPage: OCRPage,
        modelInput: String,
        findings: [DetectedSpan],
        diagnostics: [String],
        previewDiagnostics: [String]
    ) -> DetectionDebugEntry {
        DetectionDebugEntry(
            title: "Bilddiagnose",
            textSourceLabel: "Apple Vision OCR",
            rawText: ocrPage.combinedText,
            normalizedText: modelInput,
            findings: findings,
            diagnostics: diagnostics,
            previewDiagnostics: previewDiagnostics
        )
    }
}

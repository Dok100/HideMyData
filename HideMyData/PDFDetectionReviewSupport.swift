import Foundation
import PDFKit

struct PDFPageDetectionReviewResult {
    let visibleDebugSpans: [DetectedSpan]
    let reviewCandidates: [ReviewFindingCandidate]
    let previewDiagnostics: [String]
    let totalRects: Int
}

enum PDFDetectionReviewSupport {
    static func resolvePageDetections(
        spans: [DetectedSpan],
        source: PDFPageTextSource,
        page: PDFPage,
        offsetMap: [Int],
        contextualSupplementalSpans: [DetectedSpan],
        ocrSupplemental: ([DetectedSpan], [String]),
        suppressHeaderLikeFinding: (DetectedSpan, String) -> Bool,
        boundingRects: (DetectedSpan, PDFPageTextSource, PDFPage) -> [CGRect],
        rectsViaOCRFallback: ([DetectedSpan], PDFPage) async -> [(CGRect, DetectedSpan)]
    ) async -> PDFPageDetectionReviewResult {
        let visibleDebugSpans = (spans + contextualSupplementalSpans + ocrSupplemental.0)
            .filter { !suppressHeaderLikeFinding($0, source.text) }

        var reviewCandidates: [ReviewFindingCandidate] = []
        var pageReviewCandidates: [ReviewFindingCandidate] = []
        var totalRects = 0
        var unmapped: [DetectedSpan] = []

        for span in visibleDebugSpans {
            let (translated, rects) = translatedSpanAndRects(
                for: span,
                source: source,
                page: page,
                offsetMap: offsetMap,
                boundingRects: boundingRects
            )
            if rects.isEmpty {
                unmapped.append(translated)
            } else {
                let expandedRects = PDFReviewContextSupport.expandedContextRects(
                    for: translated,
                    baseRects: rects,
                    pageText: source.text,
                    on: page
                )
                let candidate = ReviewFindingCandidate(
                    category: translated.category,
                    snippet: translated.text,
                    source: translated.source,
                    confidence: translated.confidence,
                    pageIndex: nil,
                    rects: expandedRects
                )
                reviewCandidates.append(candidate)
                pageReviewCandidates.append(candidate)
                totalRects += expandedRects.count
            }
        }

        if !unmapped.isEmpty, case .nativeText = source {
            let recovered = await rectsViaOCRFallback(unmapped, page)
            let grouped = Dictionary(grouping: recovered, by: \.1.id)
            for span in unmapped {
                guard let matches = grouped[span.id], !matches.isEmpty else { continue }
                let rects = PDFReviewContextSupport.expandedContextRects(
                    for: span,
                    baseRects: matches.map(\.0),
                    pageText: source.text,
                    on: page
                )
                let candidate = ReviewFindingCandidate(
                    category: span.category,
                    snippet: span.text,
                    source: span.source,
                    confidence: span.confidence,
                    pageIndex: nil,
                    rects: rects
                )
                reviewCandidates.append(candidate)
                pageReviewCandidates.append(candidate)
                totalRects += rects.count
            }
        }

        for span in contextualSupplementalSpans + ocrSupplemental.0 {
            let rects = boundingRects(span, source, page)
            guard !rects.isEmpty else { continue }
            let candidate = ReviewFindingCandidate(
                category: span.category,
                snippet: span.text,
                source: span.source,
                confidence: span.confidence,
                pageIndex: nil,
                rects: PDFReviewContextSupport.deduplicatedRects(rects)
            )
            reviewCandidates.append(candidate)
            pageReviewCandidates.append(candidate)
            totalRects += rects.count
        }

        return PDFPageDetectionReviewResult(
            visibleDebugSpans: visibleDebugSpans,
            reviewCandidates: reviewCandidates,
            previewDiagnostics: PDFReviewContextSupport.previewDiagnosticsLines(for: pageReviewCandidates) + ocrSupplemental.1,
            totalRects: totalRects
        )
    }

    private static func translatedSpanAndRects(
        for span: DetectedSpan,
        source: PDFPageTextSource,
        page: PDFPage,
        offsetMap: [Int],
        boundingRects: (DetectedSpan, PDFPageTextSource, PDFPage) -> [CGRect]
    ) -> (DetectedSpan, [CGRect]) {
        let (start, end) = OCRNormalizer.translateRange(
            start: span.start,
            end: span.end,
            map: offsetMap,
            originalCount: source.text.count
        )
        let translated = DetectedSpan(
            category: span.category,
            text: span.text,
            start: start,
            end: end,
            confidence: span.confidence,
            source: span.source
        )
        return (translated, boundingRects(translated, source, page))
    }
}

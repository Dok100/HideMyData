import Foundation
import CoreGraphics

struct ImageRecoveredPreview {
    let finding: ReviewFinding
    let rects: [CGRect]
}

enum ImageReviewRecoverySupport {
    static func missingSupplementalRecoveries(
        candidates: [ImageSupplementalOCRCandidate],
        pixelRectFromNormalized: (CGRect) -> CGRect,
        isRectMostlyVisible: (CGRect) -> Bool
    ) -> [ImageRecoveredPreview] {
        candidates.compactMap { candidate in
            let pixelRects = candidate.normalizedRects.map(pixelRectFromNormalized)
            let alreadyVisible = pixelRects.contains(where: isRectMostlyVisible)
            guard !alreadyVisible else { return nil }

            return ImageRecoveredPreview(
                finding: ReviewFinding(
                    category: candidate.span.category,
                    snippet: candidate.span.text,
                    source: candidate.span.source,
                    confidence: candidate.span.confidence,
                    pageIndex: nil
                ),
                rects: pixelRects
            )
        }
    }

    static func windowRecipientPreludeRecoveries(
        page: OCRPage,
        pixelRectFromNormalized: (CGRect) -> CGRect,
        isRectMostlyVisible: (CGRect) -> Bool
    ) -> [ImageRecoveredPreview] {
        let recoveredCandidates = ImageOCRSupplementalAnalyzer.recoveredWindowRecipientPreludeCandidates(
            in: page,
            isNormalizedRectVisible: { normalizedRect in
                isRectMostlyVisible(pixelRectFromNormalized(normalizedRect))
            }
        )

        return recoveredCandidates.map { candidate in
            ImageRecoveredPreview(
                finding: ReviewFinding(
                    category: candidate.span.category,
                    snippet: candidate.span.text,
                    source: candidate.span.source,
                    confidence: candidate.span.confidence,
                    pageIndex: nil
                ),
                rects: candidate.normalizedRects.map(pixelRectFromNormalized)
            )
        }
    }

    static func isRectMostlyVisible(_ rect: CGRect, existingPreviewRects: [CGRect]) -> Bool {
        existingPreviewRects.contains { existing in
            let overlapRect = existing.intersection(rect)
            guard !overlapRect.isNull else { return false }

            let candidateArea = max(rect.width * rect.height, 1)
            let overlapArea = overlapRect.width * overlapRect.height
            return overlapArea / candidateArea >= 0.6
        }
    }
}

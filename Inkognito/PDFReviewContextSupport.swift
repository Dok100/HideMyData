import CoreGraphics
import Foundation
import PDFKit

enum PDFReviewContextSupport {
    static func previewDiagnosticsLines(for candidates: [ReviewFindingCandidate]) -> [String] {
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

    static func expandedContextRects(
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

    static func deduplicatedRects(_ rects: [CGRect]) -> [CGRect] {
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

    private static func contextualRedactionLabelRects(
        for span: DetectedSpan,
        in pageText: String,
        on page: PDFPage
    ) -> [CGRect] {
        var matches: [CGRect] = []
        for line in PDFTextContextSupport.contextualRedactionLabelLines(for: span, in: pageText) {
            matches.append(contentsOf: rects(for: line, on: page))
        }

        return deduplicatedRects(matches)
    }

    private static func rects(for line: NativePDFPageTextLine, on page: PDFPage) -> [CGRect] {
        guard let selection = page.selection(for: line.range) else {
            let occurrence = PDFTextRectResolver.occurrenceIndex(of: line.text, in: page.string ?? "", start: line.range.location)
            return PDFTextRectResolver.rectsByTextSearch(needle: line.text, occurrenceIndex: occurrence, on: page)
        }
        let directRects = PDFTextRectResolver.perLineRects(of: selection, on: page)
        if !directRects.isEmpty {
            return directRects
        }
        let occurrence = PDFTextRectResolver.occurrenceIndex(of: line.text, in: page.string ?? "", start: line.range.location)
        return PDFTextRectResolver.rectsByTextSearch(needle: line.text, occurrenceIndex: occurrence, on: page)
    }
}

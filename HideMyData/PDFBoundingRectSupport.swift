import Foundation
import PDFKit

enum PDFBoundingRectSupport {
    static func boundingRects(
        for span: DetectedSpan,
        source: PDFPageTextSource,
        on page: PDFPage
    ) -> [CGRect] {
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

    @MainActor
    static func rectsViaOCRFallback(
        for spans: [DetectedSpan],
        on page: PDFPage,
        ocrPageProvider: @MainActor (PDFPage) async -> OCRPage?
    ) async -> [(CGRect, DetectedSpan)] {
        guard let ocrPage = await ocrPageProvider(page), !ocrPage.combinedText.isEmpty else { return [] }
        let pageBounds = page.bounds(for: .mediaBox)
        let text = ocrPage.combinedText
        var results: [(CGRect, DetectedSpan)] = []

        for span in spans where !span.text.isEmpty {
            var searchStart = text.startIndex
            while let range = text.range(of: span.text, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)
                for norm in ocrPage.normalizedBoxes(start: start, end: end) {
                    results.append((
                        CGRect(
                            x: norm.minX * pageBounds.width,
                            y: norm.minY * pageBounds.height,
                            width: norm.width * pageBounds.width,
                            height: norm.height * pageBounds.height
                        ),
                        span
                    ))
                }
                searchStart = range.upperBound
            }
        }

        return results
    }

    private static func nsRange(start: Int, end: Int, in text: String) -> NSRange? {
        guard start <= text.count, end <= text.count, start <= end else { return nil }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        let utf16Start = text.utf16.distance(
            from: text.utf16.startIndex,
            to: startIndex.samePosition(in: text.utf16) ?? text.utf16.startIndex
        )
        let utf16End = text.utf16.distance(
            from: text.utf16.startIndex,
            to: endIndex.samePosition(in: text.utf16) ?? text.utf16.startIndex
        )
        return NSRange(location: utf16Start, length: utf16End - utf16Start)
    }
}

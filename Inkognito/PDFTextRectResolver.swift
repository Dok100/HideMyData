import Foundation
import PDFKit

struct PDFTextSelectionMatch {
    let rects: [CGRect]
    let anchor: CGRect
}

enum PDFTextRectResolver {
    static func perLineRects(of selection: PDFSelection, on page: PDFPage) -> [CGRect] {
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

    static func rectsByTextSearch(needle: String, occurrenceIndex: Int? = nil, on page: PDFPage) -> [CGRect] {
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

    static func rectsByOccurrenceSearch(needle: String, occurrenceIndex: Int, on page: PDFPage) -> [CGRect]? {
        let matches = selections(for: needle, on: page)
        guard matches.indices.contains(occurrenceIndex) else { return nil }
        return matches[occurrenceIndex].rects
    }

    static func occurrenceIndex(of needle: String, in text: String, start: Int) -> Int? {
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

    static func rectsByConjoinedNameSearch(needle: String, occurrenceIndex: Int, on page: PDFPage) -> [CGRect] {
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

    static func selections(for needle: String, on page: PDFPage) -> [PDFTextSelectionMatch] {
        guard let doc = page.document, !needle.isEmpty else { return [] }
        return doc.findString(needle, withOptions: [.caseInsensitive])
            .compactMap { selection in
                let rects = perLineRects(of: selection, on: page)
                guard !rects.isEmpty else { return nil }
                let anchor = rects.reduce(.null) { partial, rect in
                    partial.isNull ? rect : partial.union(rect)
                }
                return PDFTextSelectionMatch(rects: rects, anchor: anchor)
            }
            .sorted { lhs, rhs in
                if abs(lhs.anchor.minY - rhs.anchor.minY) > 8 {
                    return lhs.anchor.minY > rhs.anchor.minY
                }
                return lhs.anchor.minX < rhs.anchor.minX
            }
    }
}

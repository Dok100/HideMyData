import Foundation

enum PDFOCRSupplementalAnalyzer {
    static func analyze(page: OCRPage) -> (spans: [DetectedSpan], diagnostics: [String]) {
        var spans: [DetectedSpan] = []
        var diagnostics: [String] = []
        let lines = page.lines.map(\.text)

        func appendLine(_ index: Int, category: String) {
            guard let span = page.lineSpan(at: index, category: category) else { return }
            spans.append(span)
        }

        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard DocumentTextHeuristics.looksLikeWindowRecipientNameLine(cleaned),
                  OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: index),
                  let candidates = OCRContextAnalyzer.windowRecipientBlockCandidates(
                    in: lines,
                    nameIndex: index,
                    allowDotsInCityTokens: true
                  )
            else { continue }

            diagnostics.append("PDF OCR supplemental recipient block at line \(index): \(cleaned)")
            for candidate in candidates {
                appendLine(candidate.lineIndex, category: candidate.category)
            }
        }

        return (deduplicatedSpans(spans), diagnostics)
    }

    private static func deduplicatedSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var seen = Set<String>()
        var unique: [DetectedSpan] = []
        for span in spans {
            let key = "\(span.category)::\(span.start)::\(span.end)::\(span.text)"
            if seen.insert(key).inserted {
                unique.append(span)
            }
        }
        return unique
    }
}

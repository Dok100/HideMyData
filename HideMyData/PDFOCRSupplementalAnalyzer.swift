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

        func nextNonEmptyLineIndex(after index: Int) -> Int? {
            guard index + 1 < page.lines.count else { return nil }
            for candidate in (index + 1)..<page.lines.count {
                let cleaned = page.lines[candidate].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return candidate
                }
            }
            return nil
        }

        func looksLikeHonorificOnlyLine(_ text: String) -> Bool {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        func appendRecipientBlock(nameIndex: Int, honorificIndex: Int? = nil, sourceLabel: String) {
            guard let candidates = OCRContextAnalyzer.windowRecipientBlockCandidates(
                in: lines,
                nameIndex: nameIndex,
                allowDotsInCityTokens: true
            ) else { return }

            if let honorificIndex {
                appendLine(honorificIndex, category: "private_person")
            }
            for candidate in candidates {
                appendLine(candidate.lineIndex, category: candidate.category)
            }
            let cleanedName = page.lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            diagnostics.append("PDF OCR supplemental recipient block (\(sourceLabel)) at line \(nameIndex): \(cleanedName)")
        }

        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if index < 6,
               looksLikeHonorificOnlyLine(cleaned),
               let nameIndex = nextNonEmptyLineIndex(after: index),
               nameIndex <= index + 2 {
                let nameLine = page.lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(nameLine) {
                    appendRecipientBlock(nameIndex: nameIndex, honorificIndex: index, sourceLabel: "top prelude")
                    continue
                }
            }

            guard DocumentTextHeuristics.looksLikeWindowRecipientNameLine(cleaned),
                  OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: index)
            else { continue }

            appendRecipientBlock(nameIndex: index, sourceLabel: "header-context")
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

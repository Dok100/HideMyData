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

        func looksLikeHonorificRecipientLeadLine(_ text: String) -> Bool {
            let cleaned = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let patterns = [
                #"(?i)^(?:herr|herrn|frau)\s+und\s+(?:herr|herrn|frau)$"#,
                #"(?i)^(?:herr|herrn|frau)/(?:herr|herrn|frau)(?:/firma)?$"#,
                #"(?i)^(?:herr|herrn|frau)(?:/firma)?$"#
            ]
            return patterns.contains { pattern in
                cleaned.range(of: pattern, options: .regularExpression) != nil
            }
        }

        func looksLikeRecipientPreludeLeadFragment(_ text: String) -> Bool {
            let cleaned = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let patterns = [
                #"(?i)^(?:herr|herrn|frau)$"#,
                #"(?i)^und\s+(?:herr|herrn|frau)$"#,
                #"(?i)^(?:herr|herrn|frau)\s+und$"#
            ]
            return patterns.contains { pattern in
                cleaned.range(of: pattern, options: .regularExpression) != nil
            }
        }

        func looksLikeRecipientPersonFragment(_ text: String) -> Bool {
            let cleaned = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return false }

            if looksLikeHonorificOnlyLine(cleaned) ||
                looksLikeHonorificRecipientLeadLine(cleaned) ||
                looksLikeRecipientPreludeLeadFragment(cleaned) ||
                PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(cleaned) {
                return true
            }

            let patterns = [
                #"(?i)^und$"#,
                #"(?i)^und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#,
                #"(?i)^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und$"#
            ]
            return patterns.contains { pattern in
                cleaned.range(of: pattern, options: .regularExpression) != nil
            }
        }

        func hasWindowRecipientContext(before index: Int) -> Bool {
            guard index > 0 else { return false }
            if OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: index, lookback: 8) {
                return true
            }

            let start = max(0, index - 8)
            for previousIndex in start..<index {
                let cleaned = page.lines[previousIndex].text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if cleaned.contains("deutsche post") ||
                    cleaned.contains("finanzamt") ||
                    cleaned.contains("dv ") ||
                    cleaned.contains("*9150*") {
                    return true
                }
            }
            return false
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

        func appendSplitPreludeRecipientBlock(startIndex: Int) -> Bool {
            let searchEnd = min(page.lines.count, startIndex + 9)
            guard startIndex + 1 < searchEnd else { return false }

            var personIndices: [Int] = [startIndex]
            var streetIndices: [Int] = []
            var postalCityIndex: Int?

            for candidateIndex in (startIndex + 1)..<searchEnd {
                let cleaned = page.lines[candidateIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }

                if DocumentTextHeuristics.looksLikeGermanStreetLine(cleaned) {
                    streetIndices = [candidateIndex]
                    continue
                }

                if streetIndices.isEmpty,
                   PIIDetectorSpanSanitizationSupport.looksLikeStreetNameOnlyLine(cleaned),
                   let houseNumberIndex = nextNonEmptyLineIndex(after: candidateIndex),
                   houseNumberIndex < searchEnd {
                    let houseNumber = page.lines[houseNumberIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if PIIDetectorSpanSanitizationSupport.looksLikeHouseNumberOnlyLine(houseNumber) {
                        streetIndices = [candidateIndex, houseNumberIndex]
                        continue
                    }
                }

                if let lastStreetIndex = streetIndices.last,
                   candidateIndex > lastStreetIndex,
                   DocumentTextHeuristics.looksLikePostalCityLine(cleaned, allowDotsInCityTokens: true) {
                    postalCityIndex = candidateIndex
                    break
                }

                if streetIndices.isEmpty,
                   looksLikeRecipientPersonFragment(cleaned) {
                    personIndices.append(candidateIndex)
                }
            }

            guard !streetIndices.isEmpty, let postalCityIndex else { return false }
            let nameIndices = personIndices.dropFirst()
            guard !nameIndices.isEmpty else { return false }

            let hasPlausibleNameTail = nameIndices.contains { index in
                let cleaned = page.lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
                return PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(cleaned)
            }
            guard hasPlausibleNameTail else { return false }

            for index in personIndices {
                appendLine(index, category: "private_person")
            }
            for streetIndex in streetIndices {
                appendLine(streetIndex, category: "private_address")
            }
            appendLine(postalCityIndex, category: "private_address")
            let summary = personIndices.map { page.lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " | ")
            diagnostics.append("PDF OCR supplemental recipient block (split prelude) at line \(startIndex): \(summary)")
            return true
        }

        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if index < 32,
               hasWindowRecipientContext(before: index),
               (looksLikeHonorificRecipientLeadLine(cleaned) || looksLikeRecipientPreludeLeadFragment(cleaned)),
               appendSplitPreludeRecipientBlock(startIndex: index) {
                continue
            }

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
                  OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: index, lookback: 8)
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

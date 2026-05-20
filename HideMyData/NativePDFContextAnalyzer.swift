import Foundation

struct NativePDFPageTextLine {
    let text: String
    let range: NSRange
}

enum NativePDFContextAnalyzer {
    static func contextualSupplementalSpans(in text: String) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []
        let lines = pageTextLines(in: text)

        func appendSpan(for line: NativePDFPageTextLine, category: String) {
            let matched = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !matched.isEmpty,
                  let swiftRange = Range(line.range, in: text)
            else { return }
            let start = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: swiftRange.upperBound)
            spans.append(
                DetectedSpan(
                    category: category,
                    text: matched,
                    start: start,
                    end: end,
                    confidence: 0.98,
                    source: .pattern
                )
            )
        }

        func appendSpan(for line: NativePDFPageTextLine, matchedText: String, category: String) {
            let lineText = line.text
            let trimmedMatch = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMatch.isEmpty,
                  let localRange = lineText.range(
                    of: trimmedMatch,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  ),
                  let lineRange = Range(line.range, in: text)
            else { return }

            let start = text.distance(from: text.startIndex, to: lineRange.lowerBound)
                + lineText.distance(from: lineText.startIndex, to: localRange.lowerBound)
            let end = start + lineText.distance(from: localRange.lowerBound, to: localRange.upperBound)
            spans.append(
                DetectedSpan(
                    category: category,
                    text: trimmedMatch,
                    start: start,
                    end: end,
                    confidence: 0.98,
                    source: .pattern
                )
            )
        }

        for (index, line) in lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let inlineMatch = inlineContextPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: inlineMatch, category: "private_person")
                continue
            }

            if let salutationMatch = inlineSalutationPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: salutationMatch, category: "private_person")
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Abweichender Ansprechpartner:") {
                appendSpan(for: line, category: "private_person")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_person") }
                if index + 2 < lines.count { appendSpan(for: lines[index + 2], category: "private_email") }
                if index + 3 < lines.count { appendSpan(for: lines[index + 3], category: "private_phone") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Lieferadresse:") ||
                cleaned.localizedCaseInsensitiveContains("Lieferanschrift:") {
                appendAddressCandidates(
                    OCRContextAnalyzer.labeledAddressBlockCandidates(
                        in: lines.map(\.text),
                        startingAt: index,
                        allowDotsInCityTokens: true
                    ),
                    from: lines,
                    into: &spans,
                    sourceText: text
                )
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Versicherungsnehmer") ||
                cleaned.localizedCaseInsensitiveContains("Darlehensnehmer") ||
                cleaned.localizedCaseInsensitiveContains("Anschlussinhaber") {
                appendAddressCandidates(
                    OCRContextAnalyzer.labeledAddressBlockCandidates(
                        in: lines.map(\.text),
                        startingAt: index,
                        allowDotsInCityTokens: true,
                        includeLabelAsAddress: false
                    ),
                    from: lines,
                    into: &spans,
                    sourceText: text
                )
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Lieferstelle") ||
                cleaned.localizedCaseInsensitiveContains("Ihre Lieferadresse") ||
                cleaned.localizedCaseInsensitiveContains("Hierauf stellen wir Ihre Rechnung aus") ||
                cleaned.localizedCaseInsensitiveContains("Rechnungsanschrift") {
                appendAddressCandidates(
                    OCRContextAnalyzer.labeledAddressBlockCandidates(
                        in: lines.map(\.text),
                        startingAt: index,
                        allowDotsInCityTokens: true
                    ),
                    from: lines,
                    into: &spans,
                    sourceText: text
                )
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Postanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Korrespondenzanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Objektanschrift") ||
                cleaned.localizedCaseInsensitiveContains("Nutzungsadresse") {
                appendAddressCandidates(
                    OCRContextAnalyzer.labeledAddressBlockCandidates(
                        in: lines.map(\.text),
                        startingAt: index,
                        allowDotsInCityTokens: true
                    ),
                    from: lines,
                    into: &spans,
                    sourceText: text
                )
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Hier liefern wir Ihren Strom hin") {
                appendSpan(for: line, category: "private_address")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_address") }
                if index + 2 < lines.count { appendSpan(for: lines[index + 2], category: "private_address") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Schriftverkehr") {
                appendSpan(for: line, category: "private_address")
                if index + 1 < lines.count { appendSpan(for: lines[index + 1], category: "private_address") }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Für Rückfragen") ||
                cleaned.localizedCaseInsensitiveContains("Fur Ruckfragen") ||
                cleaned.localizedCaseInsensitiveContains("Rueckfragen") {
                appendSpan(for: line, category: "private_person")
            }

            if cleaned.localizedCaseInsensitiveContains("Hier erreichen wir Sie bei Rückfragen") ||
                cleaned.localizedCaseInsensitiveContains("Hier erreichen wir Sie bei Rueckfragen") {
                if let contactNameLine = nativeContactNameLine(in: lines, from: index) {
                    if contactNameLine.lineIndex == index {
                        appendSpan(
                            for: lines[index],
                            matchedText: contactNameLine.matchedText,
                            category: "private_person"
                        )
                    } else {
                        appendSpan(for: lines[contactNameLine.lineIndex], category: "private_person")
                    }
                }
            }

            if looksLikeNativeRecipientNameLine(cleaned),
               let recipientBlock = resolveNativeRecipientBlock(in: lines, nameIndex: index) {
                appendSpan(for: line, category: "private_person")
                appendSpan(for: lines[recipientBlock.streetIndex], category: "private_address")
                appendSpan(for: lines[recipientBlock.postalCityIndex], category: "private_address")
            }
        }

        return deduplicatedSpans(spans)
    }

    static func pageTextLines(in text: String) -> [NativePDFPageTextLine] {
        let nsText = text as NSString
        var lines: [NativePDFPageTextLine] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines]
        ) { _, substringRange, _, _ in
            let lineText = nsText.substring(with: substringRange)
            lines.append(NativePDFPageTextLine(text: lineText, range: substringRange))
        }
        return lines
    }

    static func normalizedComparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func appendAddressCandidates(
        _ candidates: [OCRContextLineCandidate],
        from lines: [NativePDFPageTextLine],
        into spans: inout [DetectedSpan],
        sourceText: String
    ) {
        for candidate in candidates {
            guard lines.indices.contains(candidate.lineIndex) else { continue }
            let line = lines[candidate.lineIndex]
            if let matchedText = candidate.matchedText {
                let trimmedMatch = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedMatch.isEmpty,
                      let localRange = line.text.range(
                        of: trimmedMatch,
                        options: [.caseInsensitive, .diacriticInsensitive]
                      ),
                      let lineRange = Range(line.range, in: sourceText)
                else { continue }

                let start = sourceText.distance(from: sourceText.startIndex, to: lineRange.lowerBound)
                    + line.text.distance(from: line.text.startIndex, to: localRange.lowerBound)
                let end = start + line.text.distance(from: localRange.lowerBound, to: localRange.upperBound)
                spans.append(
                    DetectedSpan(
                        category: candidate.category,
                        text: trimmedMatch,
                        start: start,
                        end: end,
                        confidence: 0.98,
                        source: .pattern
                    )
                )
            } else {
                let matched = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !matched.isEmpty,
                      let swiftRange = Range(line.range, in: sourceText)
                else { continue }
                let start = sourceText.distance(from: sourceText.startIndex, to: swiftRange.lowerBound)
                let end = sourceText.distance(from: sourceText.startIndex, to: swiftRange.upperBound)
                spans.append(
                    DetectedSpan(
                        category: candidate.category,
                        text: matched,
                        start: start,
                        end: end,
                        confidence: 0.98,
                        source: .pattern
                    )
                )
            }
        }
    }

    private static func nativeContactNameLine(in lines: [NativePDFPageTextLine], from anchorIndex: Int) -> (lineIndex: Int, matchedText: String)? {
        guard !lines.isEmpty else { return nil }
        let startIndex = max(0, anchorIndex)
        let endIndex = min(lines.count - 1, startIndex + 4)

        for index in startIndex...endIndex {
            let cleaned = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let inlineMatch = inlineContextPersonName(in: cleaned) {
                return (index, inlineMatch)
            }

            if looksLikeNativeRecipientNameLine(cleaned) {
                return (index, cleaned)
            }
        }

        return nil
    }

    private static func inlineContextPersonName(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = #"(?i)\b(?:name|bestellt\s+durch|besteller(?:in)?|kund(?:e|in)|kontoinhaber)\s*:\s*([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: normalized) else {
            return nil
        }
        return String(normalized[range])
    }

    private static func inlineSalutationPersonName(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let patterns = [
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Frau|Herr)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { continue }
            return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        }
        return nil
    }

    private static func looksLikeNativeRecipientNameLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let personPattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#
        return cleaned.range(of: personPattern, options: .regularExpression) != nil
    }

    private static func resolveNativeRecipientBlock(
        in lines: [NativePDFPageTextLine],
        nameIndex: Int
    ) -> (streetIndex: Int, postalCityIndex: Int)? {
        let searchEnd = min(lines.count, nameIndex + 4)
        guard nameIndex + 1 < searchEnd else { return nil }

        for streetIndex in (nameIndex + 1)..<searchEnd {
            let streetText = lines[streetIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !streetText.isEmpty, DocumentTextHeuristics.looksLikeGermanStreetLine(streetText) else { continue }

            for cityIndex in (streetIndex + 1)..<searchEnd {
                let cityText = lines[cityIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cityText.isEmpty else { continue }
                if DocumentTextHeuristics.looksLikePostalCityLine(cityText) {
                    return (streetIndex, cityIndex)
                }
            }
        }

        return nil
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

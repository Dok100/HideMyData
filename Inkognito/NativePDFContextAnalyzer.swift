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

            if let firstName = directFieldValue(in: cleaned, label: "Vorname:") {
                appendSpan(for: line, matchedText: firstName, category: "private_person")
            }

            if let surname = directFieldValue(in: cleaned, label: "Name:") {
                appendSpan(for: line, matchedText: surname, category: "private_person")
            }

            if let surname = directFieldValue(in: cleaned, label: "Nachname:") {
                appendSpan(for: line, matchedText: surname, category: "private_person")
            }

            if let houseNumber = directFieldValue(in: cleaned, label: "Hausnr.:") ??
                directFieldValue(in: cleaned, label: "Hausnr:") ??
                directFieldValue(in: cleaned, label: "Hausnummer:") {
                appendSpan(for: line, matchedText: houseNumber, category: "private_address")
            }

            if let firstName = inlineLabeledFieldValue(in: cleaned, labels: ["Vorname"]) {
                appendSpan(for: line, matchedText: firstName, category: "private_person")
            }

            if let personValue = inlineLabeledFieldValue(in: cleaned, labels: ["Name", "Nachname"]) {
                appendSpan(for: line, matchedText: personValue, category: "private_person")
            }

            if let houseNumber = inlineLabeledFieldValue(in: cleaned, labels: ["Hausnr.", "Hausnr", "Hausnummer"]) {
                appendSpan(for: line, matchedText: houseNumber, category: "private_address")
            }

            if cleaned.compare("IBAN:", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
               let recipientBlock = resolveNativeRecipientBlockAfterLabel(in: lines, labelIndex: index) {
                appendSpan(for: lines[recipientBlock.nameIndex], category: "private_person")
                appendSpan(for: lines[recipientBlock.streetIndex], category: "private_address")
                appendSpan(for: lines[recipientBlock.postalCityIndex], category: "private_address")
                continue
            }

            if OCRRecipientHeuristics.looksLikeRecipientPreludeStart(cleaned),
               let recipientBlock = OCRRecipientHeuristics.resolveRecipientPreludeBlock(
                   in: lines.map(\.text),
                   startIndex: index,
                   allowDotsInCityTokens: true
               ) {
                appendAddressCandidates(
                    recipientBlock.candidates,
                    from: lines,
                    into: &spans,
                    sourceText: text
                )
                continue
            }

            if let inlineMatch = inlineContextPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: inlineMatch, category: "private_person")
            }

            if let salutationMatch = inlineSalutationPersonName(in: cleaned) {
                appendSpan(for: line, matchedText: salutationMatch, category: "private_person")
            }

            if let prefixedName = inlinePrefixedPersonName(in: cleaned, prefixes: ["von", "fuer", "für"]) {
                appendSpan(for: line, matchedText: prefixedName, category: "private_person")
            }

            if let directPrefixedName = directPrefixedPersonName(in: cleaned, prefixes: ["von", "fuer", "für"]) {
                appendSpan(for: line, matchedText: directPrefixedName, category: "private_person")
            }

            for honorificName in inlineHonorificPersonNames(in: cleaned) {
                appendSpan(for: line, matchedText: honorificName, category: "private_person")
            }

            for accountIdentifier in inlineContextAccountIdentifiers(in: cleaned) {
                appendSpan(for: line, matchedText: accountIdentifier, category: "account_number")
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
                if let recipientBlock = resolveNativeRecipientBlockAfterLabel(in: lines, labelIndex: index) {
                    appendSpan(for: lines[recipientBlock.nameIndex], category: "private_person")
                    appendSpan(for: lines[recipientBlock.streetIndex], category: "private_address")
                    appendSpan(for: lines[recipientBlock.postalCityIndex], category: "private_address")
                    continue
                }
                appendDirectRecipientBlock(after: index, from: lines, into: &spans)
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
                        allowDotsInCityTokens: true,
                        includeLabelAsAddress: false
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
                        allowDotsInCityTokens: true,
                        includeLabelAsAddress: false
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

            if cleaned.localizedCaseInsensitiveContains("Schriftverkehr bitte auch an") {
                if let inlineRecipient = robustInlineRecipientAddressComponents(in: lines, labelIndex: index) ??
                    inlineRecipientAddressComponents(in: lines, labelIndex: index) {
                    appendSpan(for: lines[inlineRecipient.lineIndex], matchedText: inlineRecipient.name, category: "private_person")
                    appendSpan(for: lines[inlineRecipient.lineIndex], matchedText: inlineRecipient.fullAddress, category: "private_address")
                    appendSpan(for: lines[inlineRecipient.lineIndex], matchedText: inlineRecipient.address, category: "private_address")
                    if let postalCity = trailingPostalCity(in: inlineRecipient.address) {
                        appendSpan(for: lines[inlineRecipient.lineIndex], matchedText: postalCity, category: "private_address")
                    }
                } else if index + 1 < lines.count {
                    appendSpan(for: lines[index + 1], category: "private_address")
                }
                continue
            }

            if cleaned.localizedCaseInsensitiveContains("Für Rückfragen") ||
                cleaned.localizedCaseInsensitiveContains("Fur Ruckfragen") ||
                cleaned.localizedCaseInsensitiveContains("Rueckfragen") {
                for honorificName in inlineHonorificPersonNames(in: cleaned) {
                    appendSpan(for: line, matchedText: honorificName, category: "private_person")
                }
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

            if looksLikeNativeHonorificOnlyLine(cleaned),
               let recipientBlock = resolveNativeRecipientBlockAfterHonorific(in: lines, honorificIndex: index) {
                appendSpan(for: line, category: "private_person")
                appendSpan(for: lines[recipientBlock.nameIndex], category: "private_person")
                appendSpan(for: lines[recipientBlock.streetIndex], category: "private_address")
                appendSpan(for: lines[recipientBlock.postalCityIndex], category: "private_address")
            }

            if looksLikePostalCityContinuationLine(cleaned),
               let precedingStreetIndex = nearestStreetLineIndex(before: index, in: lines),
               hasNearbyRecipientContext(around: precedingStreetIndex, in: lines) {
                appendSpan(for: line, category: "private_address")
            }

            if cleaned.compare("Eheleute", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
               let recipientBlock = resolveNativeRecipientBlockAfterLabel(in: lines, labelIndex: index) {
                appendSpan(for: line, category: "private_person")
                appendSpan(for: lines[recipientBlock.nameIndex], category: "private_person")
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
        let pattern = #"(?i)\b(?:name|teilnehmer|bestellt\s+durch|besteller(?:in)?|kund(?:e|in)|kontoinhaber)\s*:\s*([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+/[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+|[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: normalized) else {
            return nil
        }
        return String(normalized[range])
    }

    private static func inlineContextAccountIdentifiers(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = #"(?i)\b(?:auftragsnummer|auftragsnr\.?|buchungsnummer|buchungsnr\.?)\s*:\s*([A-Z0-9][A-Z0-9\-]{5,})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        return regex.matches(in: normalized, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { return nil }
            return String(normalized[range])
        }
    }

    private static func inlinePrefixedPersonName(in text: String, prefixes: [String]) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let patterns = prefixes.map { prefix in
            #"(?im)(?:^|\s)(?:\#(NSRegularExpression.escapedPattern(for: prefix)))[ \t]+((?:(?:Dr|Prof)\.?[ \t]+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:[ \t]+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2})\b"#
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { continue }
            return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        }

        return nil
    }

    private static func inlineHonorificPersonNames(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = #"(?i)\b((?:Herr|Herrn|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})(?=\s+(?:oder|und)\s+(?:Herr|Herrn|Frau)\b|[.,;:]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        return regex.matches(in: normalized, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { return nil }
            return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        }
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
        let personPattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+/[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$|^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#
        return cleaned.range(of: personPattern, options: .regularExpression) != nil
    }

    private static func looksLikeNativeHonorificOnlyLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            cleaned.compare("Herrn", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
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

    private static func resolveNativeRecipientBlockAfterHonorific(
        in lines: [NativePDFPageTextLine],
        honorificIndex: Int
    ) -> (nameIndex: Int, streetIndex: Int, postalCityIndex: Int)? {
        let searchEnd = min(lines.count, honorificIndex + 5)
        guard honorificIndex + 3 < searchEnd else { return nil }

        for nameIndex in (honorificIndex + 1)..<searchEnd {
            let nameText = lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeNativeRecipientNameLine(nameText),
                  let block = resolveNativeRecipientBlock(in: lines, nameIndex: nameIndex)
            else { continue }
            return (nameIndex, block.streetIndex, block.postalCityIndex)
        }

        return nil
    }

    private static func resolveNativeRecipientBlockAfterLabel(
        in lines: [NativePDFPageTextLine],
        labelIndex: Int
    ) -> (nameIndex: Int, streetIndex: Int, postalCityIndex: Int)? {
        let searchEnd = min(lines.count, labelIndex + 5)
        guard labelIndex + 3 < searchEnd else { return nil }

        let nameIndex = labelIndex + 1
        let nameText = lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeNativeRecipientNameLine(nameText),
              let block = resolveNativeRecipientBlock(in: lines, nameIndex: nameIndex)
        else { return nil }

        return (nameIndex, block.streetIndex, block.postalCityIndex)
    }

    private static func inlineRecipientAddressComponents(
        in lines: [NativePDFPageTextLine],
        labelIndex: Int
    ) -> (lineIndex: Int, name: String, address: String, fullAddress: String)? {
        guard labelIndex + 1 < lines.count else { return nil }

        let candidateLine = lines[labelIndex + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}),\s*(.+\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-Za-zÄÖÜäöüß\-]+){0,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(candidateLine.startIndex..<candidateLine.endIndex, in: candidateLine)
        guard let match = regex.firstMatch(in: candidateLine, options: [], range: nsRange),
              match.numberOfRanges > 2,
              let nameRange = Range(match.range(at: 1), in: candidateLine),
              let addressRange = Range(match.range(at: 2), in: candidateLine)
        else { return nil }

        let name = String(candidateLine[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let address = String(candidateLine[addressRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !address.isEmpty else { return nil }

        return (labelIndex + 1, name, address, "\(name), \(address)")
    }

    private static func robustInlineRecipientAddressComponents(
        in lines: [NativePDFPageTextLine],
        labelIndex: Int
    ) -> (lineIndex: Int, name: String, address: String, fullAddress: String)? {
        guard labelIndex + 1 < lines.count else { return nil }

        let candidateLine = lines[labelIndex + 1].text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = candidateLine.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard segments.count >= 3 else { return nil }
        let name = segments[0]
        let street = segments[1]
        let postalCity = segments[2]
        guard looksLikeNativeRecipientNameLine(name),
              DocumentTextHeuristics.looksLikeGermanStreetLine(street),
              DocumentTextHeuristics.looksLikePostalCityLine(postalCity)
        else { return nil }

        let address = "\(street), \(postalCity)"
        return (labelIndex + 1, name, address, "\(name), \(address)")
    }

    private static func directPrefixedPersonName(in text: String, prefixes: [String]) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in prefixes {
            let lowered = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let normalizedPrefix = prefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard lowered.hasPrefix(normalizedPrefix + " ") else { continue }
            let candidate = String(normalized.dropFirst(prefix.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
            if looksLikeNativeRecipientNameLine(candidate) || looksLikeHonorificName(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func directFieldValue(in text: String, label: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let lowered = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard lowered.hasPrefix(normalizedLabel) else { return nil }
        let value = String(normalized.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func inlineLabeledFieldValue(in text: String, labels: [String]) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for label in labels {
            let pattern = #"(?i)^\#(NSRegularExpression.escapedPattern(for: label))\s*:\s*(.+)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { continue }
            let value = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func appendDirectRecipientBlock(
        after labelIndex: Int,
        from lines: [NativePDFPageTextLine],
        into spans: inout [DetectedSpan]
    ) {
        guard labelIndex + 3 < lines.count else { return }
        let nameLine = lines[labelIndex + 1]
        let streetLine = lines[labelIndex + 2]
        let cityLine = lines[labelIndex + 3]
        let name = nameLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let street = streetLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let postalCity = cityLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeNativeRecipientNameLine(name),
              DocumentTextHeuristics.looksLikeGermanStreetLine(street),
              DocumentTextHeuristics.looksLikePostalCityLine(postalCity)
        else { return }

        appendDirectSpan(text: name, category: "private_person", from: nameLine, into: &spans)
        appendDirectSpan(text: street, category: "private_address", from: streetLine, into: &spans)
        appendDirectSpan(text: postalCity, category: "private_address", from: cityLine, into: &spans)
    }

    private static func appendDirectSpan(
        text matchedText: String,
        category: String,
        from line: NativePDFPageTextLine,
        into spans: inout [DetectedSpan]
    ) {
        let lineText = line.text
        let trimmedMatch = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMatch.isEmpty,
              let localRange = lineText.range(
                of: trimmedMatch,
                options: [.caseInsensitive, .diacriticInsensitive]
              )
        else { return }

        let start = line.range.location + lineText.distance(from: lineText.startIndex, to: localRange.lowerBound)
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

    private static func looksLikePostalCityContinuationLine(_ text: String) -> Bool {
        DocumentTextHeuristics.looksLikePostalCityLine(text)
    }

    private static func nearestStreetLineIndex(before index: Int, in lines: [NativePDFPageTextLine]) -> Int? {
        guard index > 0 else { return nil }
        for candidate in stride(from: index - 1, through: 0, by: -1) {
            let cleaned = lines[candidate].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if DocumentTextHeuristics.looksLikeGermanStreetLine(cleaned) {
                return candidate
            }
            if !cleaned.isEmpty {
                break
            }
        }
        return nil
    }

    private static func hasNearbyRecipientContext(around index: Int, in lines: [NativePDFPageTextLine]) -> Bool {
        let start = max(0, index - 2)
        let end = min(lines.count - 1, index + 1)
        for cursor in start...end {
            let cleaned = lines[cursor].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if PDFTextContextSupport.looksLikeRecipientMarkerLine(cleaned) ||
                looksLikeNativeRecipientNameLine(cleaned) ||
                looksLikeNativeHonorificOnlyLine(cleaned) ||
                cleaned.compare("IBAN:", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return true
            }
        }
        return false
    }

    private static func looksLikeHonorificName(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:Herr|Herrn|Frau)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func trailingPostalCity(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let pattern = #"(?i)\b(?:D\s*-?\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#
        guard let range = normalized.range(of: pattern, options: .regularExpression) else { return nil }
        return String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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

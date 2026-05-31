import Foundation

struct OCRRecipientBlock {
    let streetIndices: [Int]
    let postalCityIndex: Int
}

struct OCRRecipientLineBlock {
    let personIndices: [Int]
    let streetIndices: [Int]
    let postalCityIndex: Int

    var candidates: [OCRContextLineCandidate] {
        personIndices.map { OCRContextLineCandidate(lineIndex: $0, category: "private_person", matchedText: nil) } +
            streetIndices.map { OCRContextLineCandidate(lineIndex: $0, category: "private_address", matchedText: nil) } +
            [OCRContextLineCandidate(lineIndex: postalCityIndex, category: "private_address", matchedText: nil)]
    }
}

enum OCRRecipientHeuristics {
    static func hasNearbyOrganizationHeader(in lines: [String], before index: Int, lookback: Int = 3) -> Bool {
        guard index > 0 else { return false }
        let start = max(0, index - lookback)
        for previousIndex in start..<index {
            if DocumentTextHeuristics.looksLikeOrganizationHeaderLine(lines[previousIndex]) {
                return true
            }
        }
        return false
    }

    static func resolveWindowRecipientBlock(
        in lines: [String],
        nameIndex: Int,
        allowDotsInCityTokens: Bool
    ) -> OCRRecipientBlock? {
        let searchEnd = min(lines.count, nameIndex + 5)
        guard nameIndex + 1 < searchEnd else { return nil }

        var streetIndices: [Int] = []
        for lineIndex in (nameIndex + 1)..<searchEnd {
            let text = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if DocumentTextHeuristics.looksLikeGermanStreetLine(text) {
                streetIndices.append(lineIndex)
                continue
            }

            if !streetIndices.isEmpty,
               DocumentTextHeuristics.looksLikePostalCityLine(text, allowDotsInCityTokens: allowDotsInCityTokens) {
                return OCRRecipientBlock(streetIndices: streetIndices, postalCityIndex: lineIndex)
            }
        }

        return nil
    }

    static func resolveRecipientPreludeBlock(
        in lines: [String],
        startIndex: Int,
        allowDotsInCityTokens: Bool,
        maxLines: Int = 9
    ) -> OCRRecipientLineBlock? {
        let searchEnd = min(lines.count, startIndex + maxLines)
        guard startIndex >= 0, startIndex + 1 < searchEnd else { return nil }

        var personIndices: [Int] = [startIndex]
        var streetIndices: [Int] = []
        var postalCityIndex: Int?

        for candidateIndex in (startIndex + 1)..<searchEnd {
            let cleaned = lines[candidateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if DocumentTextHeuristics.looksLikeGermanStreetLine(cleaned) {
                streetIndices = [candidateIndex]
                continue
            }

            if streetIndices.isEmpty,
               looksLikeStreetNameOnlyLine(cleaned),
               let houseNumberIndex = nearestNonEmptyLineIndex(in: lines, after: candidateIndex),
               houseNumberIndex < searchEnd {
                let houseNumber = lines[houseNumberIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeHouseNumberOnlyLine(houseNumber) {
                    streetIndices = [candidateIndex, houseNumberIndex]
                    continue
                }
            }

            if let lastStreetIndex = streetIndices.last,
               candidateIndex > lastStreetIndex,
               DocumentTextHeuristics.looksLikePostalCityLine(cleaned, allowDotsInCityTokens: allowDotsInCityTokens) {
                postalCityIndex = candidateIndex
                break
            }

            if streetIndices.isEmpty,
               looksLikeRecipientPersonFragment(cleaned) {
                personIndices.append(candidateIndex)
            }
        }

        guard !streetIndices.isEmpty, let postalCityIndex else { return nil }
        guard personIndices.dropFirst().contains(where: { looksLikeRecipientNameLine(lines[$0]) }) else { return nil }
        return OCRRecipientLineBlock(
            personIndices: personIndices,
            streetIndices: streetIndices,
            postalCityIndex: postalCityIndex
        )
    }

    static func looksLikeRecipientPreludeStart(_ text: String) -> Bool {
        looksLikeHonorificRecipientLeadLine(text) || looksLikeRecipientPreludeLeadFragment(text)
    }

    static func hasWindowRecipientContext(in lines: [String], before index: Int, lookback: Int = 8) -> Bool {
        guard index > 0 else { return false }
        if hasNearbyOrganizationHeader(in: lines, before: index, lookback: lookback) {
            return true
        }

        let start = max(0, index - lookback)
        for previousIndex in start..<index {
            let cleaned = lines[previousIndex]
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

    private static func nearestNonEmptyLineIndex(in lines: [String], after index: Int) -> Int? {
        guard index + 1 < lines.count else { return nil }
        for candidate in (index + 1)..<lines.count {
            if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    private static func looksLikeRecipientPreludeLeadFragment(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^eheleute$"#,
            #"(?i)^(?:herr|herrn|frau)$"#,
            #"(?i)^und\s+(?:herr|herrn|frau)$"#,
            #"(?i)^(?:herr|herrn|frau)\s+und$"#
        ]
        return patterns.contains { pattern in
            cleaned.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func looksLikeHonorificOnlyLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            cleaned.compare("Herrn", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func looksLikeHonorificRecipientLeadLine(_ text: String) -> Bool {
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

    private static func looksLikeStreetNameOnlyLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.?|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeHouseNumberOnlyLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.range(of: #"^\d+[A-Za-z]?$"#, options: .regularExpression) != nil
    }

    private static func looksLikeRecipientPersonFragment(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        if looksLikeHonorificOnlyLine(cleaned) ||
            looksLikeHonorificRecipientLeadLine(cleaned) ||
            looksLikeRecipientPreludeLeadFragment(cleaned) ||
            looksLikeRecipientNameLine(cleaned) {
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

    private static func looksLikeRecipientNameLine(_ text: String) -> Bool {
        looksLikeNameishWord(text) || looksLikeSharedSurnameCoupleName(text)
    }

    private static func looksLikeSharedSurnameCoupleName(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 8, cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let nameToken = #"[A-ZÄÖÜ][A-Za-zÄÖÜäöüß]+(?:-[A-ZÄÖÜa-zäöüß]+)*"#
        let pattern = #"^\#(nameToken)\s+und\s+\#(nameToken)\s+\#(nameToken)$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeNameishWord(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3, cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let nameToken = #"[A-ZÄÖÜ][A-Za-zÄÖÜäöüß]+(?:-[A-ZÄÖÜa-zäöüß]+)*"#
        let pattern = #"^\#(nameToken)(?:\s+\#(nameToken)){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }
}

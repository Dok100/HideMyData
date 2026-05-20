import Foundation

enum PDFHeaderSuppressionSupport {
    static func shouldSuppressHeaderLikeFinding(_ span: DetectedSpan, in pageText: String) -> Bool {
        let cleanedSnippet = span.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSnippet.isEmpty else { return false }

        let normalizedSnippet = cleanedSnippet.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let compactSnippet = cleanedSnippet
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }

        let isPostalCity = cleanedSnippet.range(
            of: #"^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#,
            options: .regularExpression
        ) != nil
        let isStreetAddress = span.category == "private_address" &&
            cleanedSnippet.range(
                of: #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#,
                options: .regularExpression
            ) != nil
        let isBareCityToken = span.category == "private_person" && compactSnippet.range(
            of: #"^[a-zäöüß]{4,}$"#,
            options: .regularExpression
        ) != nil
        let isLikelyPersonName = span.category == "private_person" &&
            cleanedSnippet.range(
                of: #"(?i)^(?:herr|frau)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$|^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}(?:,\s*(?:CEO|CFO|COO|CTO|CMO))?$"#,
                options: .regularExpression
            ) != nil
        guard isPostalCity || isBareCityToken || isStreetAddress || isLikelyPersonName else { return false }

        let lines = pageText.components(separatedBy: .newlines)
        let headerKeywords = [
            "finanzamt", "finanzkasse", "moltkestr", "moltkestra", "tel", "zi.nr",
            "steuernummer", "idnr", "deutsche post", "geschäftsführung",
            "geschaftsfuhrung", "geschäftsführer", "geschaftsfuhrer",
            "handelsregister", "amtsgericht", "bankverbindung", "onlinebuchung",
            "reisebestätigung", "reisebestatigung"
        ]
        let senderKeywords = [
            "gmbh", "mbh", "ag", "ug", "kg", "ohg", "gbr", "kundin", "kunde"
        ]
        let companyHeaderPresent = lines.prefix(6).contains { line in
            let normalized = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return senderKeywords.contains(where: { normalized.contains($0) })
        }
        let firstRecipientIndex = lines.firstIndex { line in
            PDFTextContextSupport.looksLikeRecipientMarkerLine(line)
        }

        for (index, line) in lines.enumerated() {
            let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let compactLine = normalizedLine.filter { $0.isLetter || $0.isNumber }
            guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) ||
                    (!compactSnippet.isEmpty && compactLine.contains(compactSnippet))
            else { continue }

            if (isPostalCity || isStreetAddress) &&
                DocumentTextHeuristics.looksLikeOrganizationHeaderLine(line) {
                return true
            }

            let contextStart = max(0, index - 2)
            let contextEnd = min(lines.count - 1, index + 2)
            let context = lines[contextStart...contextEnd]
                .joined(separator: "\n")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            if headerKeywords.contains(where: { context.contains($0) }) {
                return true
            }
            if isLikelyPersonName,
               context.contains("geschaftsfuhrung") || context.contains("geschäftsführung") ||
                context.contains("ceo") || context.contains("cfo") ||
                context.contains("geschäftsführer") || context.contains("geschaftsfuhrer") {
                return true
            }
            if let firstRecipientIndex,
               index < firstRecipientIndex,
               senderKeywords.contains(where: { context.contains($0) }) {
                return true
            }
            if companyHeaderPresent,
               isEmbeddedSenderBlockLine(in: lines, at: index, isStreetAddress: isStreetAddress, isPostalCity: isPostalCity) {
                return true
            }
            if isPostalCity,
               context.range(of: #"\b\d{2}\.\d{2}\.\d{4}\b"#, options: .regularExpression) != nil {
                return true
            }
            if isPostalCity,
               context.range(of: #"\(?\d{3,5}\)?[ /-]?\d{2,5}[-/]\d{2,5}"#, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    private static func isEmbeddedSenderBlockLine(
        in lines: [String],
        at index: Int,
        isStreetAddress: Bool,
        isPostalCity: Bool
    ) -> Bool {
        guard index >= 0, index < lines.count else { return false }

        let previousIndex = nearestNonEmptyLineIndex(in: lines, before: index)
        let nextIndex = nearestNonEmptyLineIndex(in: lines, after: index)
        let hasRecipientMarkerNearby = (max(0, index - 2)...min(lines.count - 1, index + 1)).contains { nearbyIndex in
            PDFTextContextSupport.looksLikeRecipientMarkerLine(lines[nearbyIndex])
        }
        guard !hasRecipientMarkerNearby else { return false }

        let senderContextKeywords = ["vertrieb", "kundenservice", "kontakt", "tarif", "online", "gmbh", "ag", "mbh"]
        let previousLine = previousIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let normalizedPrevious = previousLine.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let previousLooksSenderLike =
            previousLine.contains(".") ||
            previousLine.contains(":") ||
            senderContextKeywords.contains(where: { normalizedPrevious.contains($0) })

        if isStreetAddress,
           let nextIndex,
           DocumentTextHeuristics.looksLikePostalCityLine(lines[nextIndex]),
           previousLooksSenderLike {
            return true
        }

        if isPostalCity,
           let previousIndex,
           DocumentTextHeuristics.looksLikeGermanStreetLine(lines[previousIndex]) {
            let senderPreludeIndex = nearestNonEmptyLineIndex(in: lines, before: previousIndex)
            let senderPrelude = senderPreludeIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let normalizedPrelude = senderPrelude.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if senderPrelude.contains(".") ||
                senderPrelude.contains(":") ||
                senderContextKeywords.contains(where: { normalizedPrelude.contains($0) }) {
                return true
            }
        }

        return false
    }

    private static func nearestNonEmptyLineIndex(in lines: [String], before index: Int) -> Int? {
        guard index > 0 else { return nil }
        for candidate in stride(from: index - 1, through: 0, by: -1) {
            if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
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
}

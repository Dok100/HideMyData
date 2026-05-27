import Foundation

enum PIIDetectorSpanSanitizationSupport {
    nonisolated static func sanitizeSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.compactMap { span in
            let cleanedText = sanitizedSpanText(span.text, category: span.category)
            guard !shouldDropSpan(category: span.category, text: cleanedText, source: span.source) else {
                return nil
            }
            let category = sanitizedCategory(for: span.category, text: cleanedText)
            return DetectedSpan(
                category: category,
                text: cleanedText,
                start: span.start,
                end: span.end,
                confidence: span.confidence,
                source: span.source
            )
        }
    }

    nonisolated static func cleanedSpanText(_ text: String) -> String {
        OCRNormalizer.normalize(text, mode: .native).text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func sanitizedSpanText(_ text: String, category: String) -> String {
        let cleaned = cleanedSpanText(text)
        switch category {
        case "private_address":
            return sanitizeAddressFieldArtifacts(in: cleaned)
        case "private_person":
            return sanitizeTrailingPersonLabelArtifacts(in: cleaned)
        default:
            return cleaned
        }
    }

    nonisolated static func sanitizeAddressFieldArtifacts(in text: String) -> String {
        var cleaned = text

        let leadingFieldPatterns = [
            #"(?i)^(?:straße|strasse|hausnr\.?|hausnummer|plz|ort|stadt):\s*"#,
            #"(?i)^(?:vorname|name|nachname):\s*"#
        ]

        for pattern in leadingFieldPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)^(\d{5})\s+(?:ort|stadt):?$"#,
            with: "$1",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func sanitizeTrailingPersonLabelArtifacts(in text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingLabels = [
            "Lieferadresse",
            "Lieferanschrift",
            "Rechnungsanschrift",
            "Postanschrift",
            "Korrespondenzanschrift",
            "Nutzungsadresse",
            "Objektanschrift",
            "Schriftverkehr"
        ]

        for label in trailingLabels {
            let pattern = #"(?i)^(.*?)(?:\s+|\R+)"# + NSRegularExpression.escapedPattern(for: label) + #":?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, options: [], range: range),
                  match.numberOfRanges > 1,
                  let prefixRange = Range(match.range(at: 1), in: cleaned)
            else { continue }

            let prefix = String(cleaned[prefixRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikePlausiblePersonName(prefix) {
                return prefix
            }
        }

        return cleaned
    }

    nonisolated static func sanitizedCategory(for category: String, text: String) -> String {
        if category == "custom_identifier" {
            if looksLikePostalCity(text) || looksLikeGermanStreetAddress(text) || looksLikeAddressBlock(text) {
                return "private_address"
            }
        }
        guard category == "account_number" else { return category }
        return looksLikePostalCity(text) ? "private_address" : category
    }

    nonisolated static func shouldDropSpan(category: String, text: String, source: DetectionSource) -> Bool {
        guard !text.isEmpty else { return true }

        switch category {
        case "private_person":
            if isDocumentNoise(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            if normalizedComparableText(text) == "eheleute" {
                return true
            }
            if looksLikeOrganizationSnippet(text) || personSpanContainsAddressOrContactTail(text) {
                return true
            }
            if source == .model, text.count <= 4, !looksLikeNameishWord(text) {
                return true
            }
            if source == .model, text.rangeOfCharacter(from: .decimalDigits) != nil, !text.contains(" ") {
                return true
            }
            return false

        case "private_address":
            if isDocumentNoise(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            if looksLikeCompanyAddressBlock(text) {
                return true
            }
            if looksLikeHonorificStreetCombo(text) {
                return true
            }
            if hasLeadingSentenceFragmentBeforeStreetAddress(text) {
                return true
            }
            if looksLikePostalCity(text) ||
                looksLikeGermanStreetAddress(text) ||
                looksLikeAddressBlock(text) ||
                looksLikeStreetNameOnlyLine(text) ||
                looksLikeHouseNumberOnlyLine(text) ||
                looksLikePostalCodeOnlyLine(text) ||
                looksLikeCityNameOnlyLine(text) {
                return false
            }
            if source == .model {
                return true
            }
            if source == .pattern {
                return true
            }
            return text.count < 8

        case "account_number":
            if normalizedComparableText(text).contains("bic") {
                return true
            }
            if source != .model {
                return false
            }
            if looksLikePostalCity(text) || looksLikeGermanStreetAddress(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            let digitsOnly = text.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
            let hasLetters = text.rangeOfCharacter(from: .letters) != nil
            if !hasLetters && digitsOnly.count < 12 {
                return true
            }
            return false

        case "secret":
            return looksLikeLegalBoilerplateHeading(text)

        default:
            return false
        }
    }

    nonisolated static func looksLikePostalCity(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = normalizedComparableText(cleaned)
        if normalizedText.hasSuffix("seite") {
            return false
        }
        let pattern = #"(?i)^(?:D\s*-?\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeGermanStreetAddress(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeStreetNameOnlyLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              cleaned.rangeOfCharacter(from: .decimalDigits) == nil
        else { return false }

        let pattern = #"(?i)^(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeHouseNumberOnlyLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.range(of: #"^\d+[A-Za-z]?$"#, options: .regularExpression) != nil
    }

    nonisolated static func looksLikePostalCodeOnlyLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.range(of: #"^\d{5}$"#, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeCityNameOnlyLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              cleaned.rangeOfCharacter(from: .decimalDigits) == nil
        else { return false }

        let pattern = #"(?i)^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß.\-]+(?:\s+(?:bei|an|am|im|der|den|dem|von|vor|hinter|unter|ober|sankt|st\.))?(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß.\-]+){0,3}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikePostalCity(cleaned) || looksLikeGermanStreetAddress(cleaned) {
            return true
        }
        let pattern = #"(?i)\b(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+.+\d{5}\s+[A-ZÄÖÜa-zäöüß]"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func hasLeadingSentenceFragmentBeforeStreetAddress(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeGermanStreetAddress(cleaned) else { return false }

        let pattern = #"(?i)^.+[.!?:]\s+(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeCompanyAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeOrganizationSnippet(cleaned) else { return false }
        return looksLikeGermanStreetAddress(cleaned) ||
            looksLikePostalCity(cleaned) ||
            cleaned.range(of: #"\b\d+[A-Za-z]?\b"#, options: .regularExpression) != nil
    }

    nonisolated static func personSpanContainsAddressOrContactTail(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = normalizedComparableText(cleaned)
        guard normalizedText.contains("frau") || normalizedText.contains("herr") else { return false }

        if looksLikeGermanStreetAddress(cleaned) {
            return true
        }

        let bannedFragments = [
            "email", "telefon", "mobil", "kontakt", "ansprechpartner",
            "strasse", "straße", "str", "weg", "allee", "platz", "gasse", "ring", "ufer", "steig", "steige"
        ]
        return bannedFragments.contains { fragment in
            cleaned.localizedCaseInsensitiveContains(fragment) || normalizedText.contains(normalizedComparableText(fragment))
        }
    }

    nonisolated static func looksLikeHonorificStreetCombo(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikePostalCity(cleaned),
              looksLikeGermanStreetAddress(cleaned)
        else { return false }

        let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeLeadingConjunctionAddressTail(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeGermanStreetAddress(cleaned) else { return false }

        let pattern = #"(?i)^und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeConjoinedCoupleName(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\b[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeNameishWord(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3, cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let pattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func looksLikeTaxOfficeHeader(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        return normalizedText.contains("finanzamt") ||
            normalizedText.contains("finanzkasse") ||
            normalizedText.contains("steuernummer") ||
            normalizedText.contains("idnr") ||
            normalizedText.contains("bescheid")
    }

    nonisolated static func looksLikeOrganizationSnippet(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func isDocumentNoise(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        let bannedFragments = [
            "eink", "einkommensteuer", "kirchensteuer", "solidaritatszuschlag",
            "fortsotzung", "fortsetzung", "nachsteseite", "nachsteselte",
            "selto", "luszetch", "reste", "ruckfragen", "angeben"
        ]
        return bannedFragments.contains { normalizedText.contains($0) }
    }

    nonisolated static func looksLikeTermsAndConditionsDocument(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        let markers = [
            "allgemeinegeschaftsbedingungen", "geltungsbereich", "vertragsschluss",
            "eigentumsvorbehalt", "schlussbestimmungen", "streitbeilegung",
            "vertragsbestandteil", "mitwirkungspflichten", "nacherfullung"
        ]
        let hitCount = markers.reduce(into: 0) { count, marker in
            if normalizedText.contains(marker) {
                count += 1
            }
        }
        return hitCount >= 3 || normalizedText.contains("allgemeinegeschaftsbedingungen")
    }

    nonisolated static func looksLikeLegalBoilerplateHeading(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        let headings: Set<String> = [
            "geltungsbereich", "vertragsschluss", "eigentumsvorbehalt",
            "schlussbestimmungen", "streitbeilegung", "widerrufsrecht",
            "gewahrleistung", "haftung", "zahlungsbedingungen", "datenschutz"
        ]
        return headings.contains(normalizedText)
    }

    nonisolated static func looksLikePlausiblePersonName(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let patterns = [
            #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$"#,
            #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+/[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#,
            #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+$"#,
            #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$"#
        ]

        return patterns.contains { pattern in
            cleaned.range(of: pattern, options: .regularExpression) != nil
        }
    }

    nonisolated static func deduplicateExactSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var bestByKey: [String: DetectedSpan] = [:]
        var order: [String] = []

        for span in spans {
            let key = exactSpanKey(span)
            if let existing = bestByKey[key] {
                if span.confidence > existing.confidence {
                    bestByKey[key] = span
                }
            } else {
                bestByKey[key] = span
                order.append(key)
            }
        }

        return order.compactMap { bestByKey[$0] }
    }

    nonisolated static func suppressConjoinedNameFragments(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.filter { candidate in
            guard candidate.category == "private_person" else { return true }

            let normalizedCandidate = normalizedComparableText(candidate.text)
            guard !normalizedCandidate.isEmpty,
                  !looksLikeConjoinedCoupleName(candidate.text)
            else { return true }

            let candidateLength = max(candidate.end - candidate.start, 1)
            return !spans.contains { other in
                guard other.id != candidate.id,
                      other.category == "private_person",
                      looksLikeConjoinedCoupleName(other.text)
                else { return false }

                let normalizedOther = normalizedComparableText(other.text)
                guard normalizedOther.count > normalizedCandidate.count,
                      normalizedOther.contains(normalizedCandidate)
                else { return false }

                if other.start <= candidate.start && other.end >= candidate.end {
                    return true
                }

                let overlapStart = max(candidate.start, other.start)
                let overlapEnd = min(candidate.end, other.end)
                guard overlapEnd > overlapStart else { return false }

                let overlapRatio = Double(overlapEnd - overlapStart) / Double(candidateLength)
                return overlapRatio >= 0.7
            }
        }
    }

    nonisolated static func suppressLeadingConjunctionAddressSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.filter { candidate in
            guard candidate.category == "private_address" else { return true }
            return !looksLikeLeadingConjunctionAddressTail(candidate.text)
        }
    }

    nonisolated static func suppressLegalBoilerplateFalsePositives(_ spans: [DetectedSpan], in text: String) -> [DetectedSpan] {
        let suppressPersonNoise = looksLikeTermsAndConditionsDocument(text)

        return spans.filter { candidate in
            if candidate.category == "secret",
               looksLikeLegalBoilerplateHeading(candidate.text) {
                return false
            }

            if suppressPersonNoise,
               candidate.category == "private_person",
               !looksLikePlausiblePersonName(candidate.text) {
                return false
            }

            return true
        }
    }

    nonisolated static func suppressContainedCustomIdentifierSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.filter { candidate in
            guard candidate.category == "custom_identifier" else {
                return true
            }

            let normalizedCandidate = normalizedComparableText(candidate.text)
            guard !normalizedCandidate.isEmpty else { return false }

            let candidateLength = candidate.end - candidate.start
            return !spans.contains { other in
                guard other.id != candidate.id,
                      other.end > other.start
                else { return false }

                let otherLength = other.end - other.start
                guard otherLength > candidateLength else { return false }

                if other.start <= candidate.start && other.end >= candidate.end {
                    return true
                }

                let overlapStart = max(candidate.start, other.start)
                let overlapEnd = min(candidate.end, other.end)
                guard overlapEnd > overlapStart else { return false }

                let overlapLength = overlapEnd - overlapStart
                let overlapRatio = Double(overlapLength) / Double(candidateLength)
                guard overlapRatio >= 0.75 else { return false }

                if other.category != "custom_identifier" {
                    if shouldPreserveStrongCustomIdentifier(candidate, inside: other) {
                        return false
                    }
                    return true
                }

                return normalizedComparableText(other.text).contains(normalizedCandidate)
            }
        }
    }

    nonisolated static func shouldPreserveStrongCustomIdentifier(_ candidate: DetectedSpan, inside other: DetectedSpan) -> Bool {
        let normalizedCandidate = normalizedComparableText(candidate.text)
        guard !normalizedCandidate.isEmpty else { return false }

        if candidate.text.rangeOfCharacter(from: .decimalDigits) != nil {
            return false
        }

        let candidateTokenCount = candidate.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .count

        guard candidateTokenCount >= 2 else { return false }

        if other.category == "private_person",
           isHonorificWrappedPerson(candidate: normalizedCandidate, wrapper: other.text) {
            return true
        }

        return false
    }

    nonisolated static func isHonorificWrappedPerson(candidate: String, wrapper: String) -> Bool {
        let normalizedWrapper = normalizedComparableText(wrapper)
        guard normalizedWrapper.count > candidate.count,
              normalizedWrapper.contains(candidate)
        else { return false }

        let pattern = #"^(frau|herr)\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        let fullRange = NSRange(normalizedWrapper.startIndex..<normalizedWrapper.endIndex, in: normalizedWrapper)
        guard let match = regex.firstMatch(in: normalizedWrapper, options: [], range: fullRange),
              match.range.location != NSNotFound,
              let matchRange = Range(match.range, in: normalizedWrapper)
        else {
            return false
        }

        let stripped = String(normalizedWrapper[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped == candidate
    }

    nonisolated static func mergeEquivalentSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var groups: [String: [DetectedSpan]] = [:]
        var order: [String] = []

        for span in spans {
            let key = equivalentSpanKey(span)
            if groups[key] == nil {
                groups[key] = []
                order.append(key)
            }
            groups[key, default: []].append(span)
        }

        return order.compactMap { key in
            guard let group = groups[key], let primary = preferredSpan(in: group) else { return nil }
            let mergedSource = mergedSource(for: group)
            let mergedConfidence = group.map(\.confidence).max() ?? primary.confidence
            return DetectedSpan(
                category: primary.category,
                text: primary.text,
                start: primary.start,
                end: primary.end,
                confidence: mergedConfidence,
                source: mergedSource
            )
        }
    }

    nonisolated static func preferredSpan(in group: [DetectedSpan]) -> DetectedSpan? {
        group.max { lhs, rhs in
            spanRank(lhs) < spanRank(rhs)
        }
    }

    nonisolated static func spanRank(_ span: DetectedSpan) -> Int {
        var rank = 0
        if span.category != "custom_identifier" { rank += 100 }
        switch span.source {
        case .model: rank += 30
        case .mixed: rank += 20
        case .pattern: rank += 10
        }
        rank += Int(span.confidence * 10)
        return rank
    }

    nonisolated static func mergedSource(for group: [DetectedSpan]) -> DetectionSource {
        let sources = Set(group.map(\.source))
        if sources.count > 1 || sources.contains(.mixed) {
            return .mixed
        }
        return group.first?.source ?? .pattern
    }

    nonisolated static func exactSpanKey(_ span: DetectedSpan) -> String {
        let textKey = span.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [
            span.category,
            span.source.rawValue,
            "\(span.start)",
            "\(span.end)",
            textKey
        ].joined(separator: "::")
    }

    nonisolated static func equivalentSpanKey(_ span: DetectedSpan) -> String {
        let textKey = span.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [
            "\(span.start)",
            "\(span.end)",
            textKey
        ].joined(separator: "::")
    }

    nonisolated static func normalizedComparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

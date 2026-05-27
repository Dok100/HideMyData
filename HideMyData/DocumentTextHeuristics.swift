import Foundation

enum DocumentTextHeuristics {
    static func lowSignalOCRText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .count
        let lettersAndNumbers = trimmed.filter { $0.isLetter || $0.isNumber }.count
        return words < 6 || lettersAndNumbers < 28
    }

    static func salutationPersonName(in text: String) -> String? {
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

    static func standaloneFieldLabelKey(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let mappings: [(label: String, key: String)] = [
            ("Vorname", "vorname"),
            ("Name", "name"),
            ("Nachname", "name"),
            ("Straße", "strasse"),
            ("Strasse", "strasse"),
            ("Strae", "strasse"),
            ("Street", "strasse"),
            ("Hausnr.", "hausnr"),
            ("Hausnr", "hausnr"),
            ("Hausnummer", "hausnr"),
            ("PLZ", "plz"),
            ("Postleitzahl", "plz"),
            ("Ort", "ort"),
            ("Stadt", "ort")
        ]

        for mapping in mappings {
            let pattern = #"(?i)^\#(NSRegularExpression.escapedPattern(for: mapping.label))\s*:\s*$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if regex.firstMatch(in: normalized, options: [], range: nsRange) != nil {
                return mapping.key
            }
        }

        return nil
    }

    static func strongCustomIdentifierText(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let tokenCount = cleaned.split(separator: " ").count
        return tokenCount >= 2
    }

    static func looksLikeWindowRecipientNameLine(_ text: String) -> Bool {
        let cleaned = normalizedComparableText(text)
        let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    static func looksLikeOrganizationHeaderLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    static func looksLikeGermanStreetLine(_ text: String) -> Bool {
        let cleaned = normalizedComparableText(text)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    static func looksLikePostalCityLine(_ text: String, allowDotsInCityTokens: Bool = true) -> Bool {
        let cleaned = normalizedComparableText(text)
        let cityTokenPattern = allowDotsInCityTokens
            ? #"[A-Za-zÄÖÜäöüß.]+"#
            : #"[A-Za-zÄÖÜäöüß]+"#
        let pattern = #"(?i)^(?:D\s*-?\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß]\#(cityTokenPattern)(?:[ -]\#(cityTokenPattern)){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedComparableText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

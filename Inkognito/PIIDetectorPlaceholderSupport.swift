import Foundation

enum PIIDetectorPlaceholderSupport {
    nonisolated static func placeholderize(text: String, spans: [DetectedSpan]) -> TextAnonymizationResult {
        let selectedSpans = selectNonOverlappingSpans(spans)

        var assignedPlaceholders: [String: String] = [:]
        var placeholderByKey: [String: String] = [:]
        var placeholderCounters: [String: Int] = [:]
        var anonymizedText = text

        for span in selectedSpans.sorted(by: { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end > rhs.end }
            return lhs.start > rhs.start
        }) {
            guard span.start >= 0, span.end <= anonymizedText.count, span.end > span.start else { continue }

            let categoryBase = placeholderBase(for: span.category)
            let mappingKey = placeholderMappingKey(for: span)
            let placeholder: String

            if let existing = placeholderByKey[mappingKey] {
                placeholder = existing
            } else {
                let nextIndex = (placeholderCounters[categoryBase] ?? 0) + 1
                placeholderCounters[categoryBase] = nextIndex
                placeholder = "[\(categoryBase)_\(nextIndex)]"
                placeholderByKey[mappingKey] = placeholder
                assignedPlaceholders[placeholder] = span.text
            }

            let startIndex = anonymizedText.index(anonymizedText.startIndex, offsetBy: span.start)
            let endIndex = anonymizedText.index(anonymizedText.startIndex, offsetBy: span.end)
            anonymizedText.replaceSubrange(startIndex..<endIndex, with: placeholder)
        }

        return TextAnonymizationResult(
            anonymizedText: anonymizedText,
            replacementCount: selectedSpans.count,
            placeholders: assignedPlaceholders
        )
    }

    nonisolated static func restorePlaceholders(in text: String, placeholders: [String: String]) -> TextRestorationResult {
        guard !placeholders.isEmpty else {
            return TextRestorationResult(restoredText: text, replacementCount: 0, unresolvedPlaceholders: [], suspiciousTokens: [])
        }

        var restoredText = text
        var replacementCount = 0

        let orderedPlaceholders = placeholders.keys.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs < rhs }
            return lhs.count > rhs.count
        }

        for placeholder in orderedPlaceholders {
            guard let originalValue = placeholders[placeholder] else { continue }
            let pattern = placeholderRegexPattern(for: placeholder)

            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(restoredText.startIndex..<restoredText.endIndex, in: restoredText)
            let matches = regex.matches(in: restoredText, range: range)
            guard !matches.isEmpty else { continue }

            replacementCount += matches.count
            restoredText = regex.stringByReplacingMatches(in: restoredText, range: range, withTemplate: originalValue)
        }

        let unresolved = orderedPlaceholders.filter { placeholder in
            let pattern = placeholderRegexPattern(for: placeholder)
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(restoredText.startIndex..<restoredText.endIndex, in: restoredText)
            return regex.firstMatch(in: restoredText, range: range) != nil
        }

        let suspiciousTokens = detectSuspiciousPlaceholderTokens(in: restoredText, expectedPlaceholders: orderedPlaceholders)

        return TextRestorationResult(
            restoredText: restoredText,
            replacementCount: replacementCount,
            unresolvedPlaceholders: unresolved,
            suspiciousTokens: suspiciousTokens
        )
    }

    nonisolated private static func selectNonOverlappingSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        let sorted = spans.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let lhsPriority = placeholderSelectionPriority(for: lhs.category)
            let rhsPriority = placeholderSelectionPriority(for: rhs.category)
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            let lhsLength = lhs.end - lhs.start
            let rhsLength = rhs.end - rhs.start
            if lhsLength != rhsLength { return lhsLength > rhsLength }
            return lhs.confidence > rhs.confidence
        }

        var accepted: [DetectedSpan] = []
        for candidate in sorted {
            guard candidate.end > candidate.start else { continue }
            let overlaps = accepted.contains { existing in
                max(candidate.start, existing.start) < min(candidate.end, existing.end)
            }
            if !overlaps {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    nonisolated private static func placeholderSelectionPriority(for category: String) -> Int {
        switch category {
        case "private_person", "private_address", "private_phone", "private_email", "private_date", "account_number", "secret":
            return 2
        case "custom_identifier":
            return 1
        default:
            return 0
        }
    }

    nonisolated private static func placeholderBase(for category: String) -> String {
        switch category {
        case "private_person": return "NAME"
        case "private_address": return "ADRESSE"
        case "private_date": return "DATUM"
        case "private_email": return "EMAIL"
        case "private_phone": return "TELEFON"
        case "account_number": return "NUMMER"
        case "secret": return "GEHEIM"
        case "custom_identifier": return "PLATZHALTER"
        default:
            let compact = category
                .uppercased()
                .folding(options: [.diacriticInsensitive], locale: .current)
                .replacingOccurrences(of: "PRIVATE_", with: "")
                .replacingOccurrences(of: "[^A-Z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return compact.isEmpty ? "PII" : compact
        }
    }

    nonisolated private static func placeholderMappingKey(for span: DetectedSpan) -> String {
        let normalizedText = span.text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(placeholderBase(for: span.category))::\(normalizedText)"
    }

    nonisolated private static func placeholderRegexPattern(for placeholder: String) -> String {
        let rawKey = placeholder.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let pieces = rawKey.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2 else {
            let escaped = NSRegularExpression.escapedPattern(for: rawKey)
            return "(?i)(?<![A-ZÄÖÜa-zäöüß0-9])\\[?\\s*\(escaped)\\s*\\]?(?![A-ZÄÖÜa-zäöüß0-9])"
        }

        let category = NSRegularExpression.escapedPattern(for: String(pieces[0]))
        let index = NSRegularExpression.escapedPattern(for: String(pieces[1]))
        return "(?i)(?<![A-ZÄÖÜa-zäöüß0-9])\\[?\\s*\(category)\\s*[-_ ]\\s*\(index)\\s*\\]?(?![A-ZÄÖÜa-zäöüß0-9])"
    }

    nonisolated private static func canonicalPlaceholderToken(_ token: String) -> String {
        token
            .uppercased()
            .replacingOccurrences(of: "[\\[\\]\\s-]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    nonisolated private static func detectSuspiciousPlaceholderTokens(in text: String, expectedPlaceholders: [String]) -> [String] {
        let expectedCanonical = Set(expectedPlaceholders.map {
            canonicalPlaceholderToken($0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
        })

        let pattern = "(?i)\\[?\\s*[A-ZÄÖÜa-zäöü]+\\s*[-_ ]\\s*\\d+\\s*\\]?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var suspicious: [String] = []
        var seen = Set<String>()

        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            let canonical = canonicalPlaceholderToken(token)
            guard expectedCanonical.contains(canonical), seen.insert(token).inserted else { continue }
            suspicious.append(token)
        }

        return suspicious.sorted()
    }
}

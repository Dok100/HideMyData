import Foundation

enum PIIDetectorPatternDiagnosticsSupport {
    nonisolated static func printPatternDiagnostics(
        _ diagnostics: PatternMatcher.Diagnostics,
        postProcessed: [DetectedSpan],
        in text: String
    ) {
        for line in patternDiagnosticsLines(diagnostics, postProcessed: postProcessed, in: text) {
            print(line)
        }
    }

    nonisolated static func patternDiagnosticsLines(
        _ diagnostics: PatternMatcher.Diagnostics,
        postProcessed: [DetectedSpan],
        in text: String
    ) -> [String] {
        let storageLine = "PatternMatcher custom rule storage: \(diagnostics.storagePath) [exists=\(diagnostics.storageFileExists)]"
        let legacyStorageLine = "PatternMatcher legacy custom rule storage: \(diagnostics.legacyStoragePath) [exists=\(diagnostics.legacyStorageFileExists)]"

        guard !diagnostics.loadedCustomPatterns.isEmpty else {
            return [
                storageLine,
                legacyStorageLine,
                "PatternMatcher custom rules loaded (0): <none>"
            ]
        }

        let loadedRules = diagnostics.loadedCustomPatterns.map { descriptor in
            "\(descriptor.label) [\(descriptor.category)] = \(descriptor.value)"
        }.joined(separator: " | ")

        let jonasRules = diagnostics.loadedCustomPatterns.filter {
            $0.value.compare("Jonas Weber", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            $0.label.localizedCaseInsensitiveContains("Jonas Weber")
        }

        let rawCustomSpans = diagnostics.rawCustomMatches.map { spanDescription($0) }.joined(separator: " | ")

        let survivingCustomSpans = postProcessed.filter { span in
            diagnostics.loadedCustomPatterns.contains { descriptor in
                descriptor.category == span.category &&
                descriptor.value.compare(span.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        let survivingDescriptions = survivingCustomSpans.map { spanDescription($0) }.joined(separator: " | ")

        let jonasInText = text.range(of: "Jonas Weber", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let jonasRaw = diagnostics.rawCustomMatches.filter {
            $0.text.compare("Jonas Weber", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let jonasSurviving = survivingCustomSpans.filter {
            $0.text.compare("Jonas Weber", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        return [
            storageLine,
            legacyStorageLine,
            "PatternMatcher custom rules loaded (\(diagnostics.loadedCustomPatterns.count)): \(loadedRules)",
            "PatternMatcher custom rule contains 'Jonas Weber': \(jonasRules.isEmpty ? "no" : "yes")",
            "PatternMatcher raw custom matches: \(rawCustomSpans.isEmpty ? "<none>" : rawCustomSpans)",
            "PatternMatcher surviving custom matches: \(survivingDescriptions.isEmpty ? "<none>" : survivingDescriptions)",
            "PatternMatcher Jonas Weber diagnostics: textContains=\(jonasInText) rawCustomSpan=\(!jonasRaw.isEmpty) survivingCustomSpan=\(!jonasSurviving.isEmpty)"
        ]
    }

    nonisolated static func spanDescription(_ span: DetectedSpan) -> String {
        "[\(detectionSourceLabel(span.source))] \(span.category) '\(span.text)' @ \(span.start)-\(span.end)"
    }

    nonisolated static func detectionSourceLabel(_ source: DetectionSource) -> String {
        switch source {
        case .model: return "Modell"
        case .pattern: return "Regex"
        case .mixed: return "Modell + Regex"
        }
    }
}

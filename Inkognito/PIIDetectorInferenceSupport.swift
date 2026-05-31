import Foundation
@preconcurrency import OpenMedKit

enum PIIDetectorInferenceSupport {
    nonisolated static func detect(
        _ text: String,
        model: OpenMed,
        supplementalSpans: (String) -> [DetectedSpan],
        postProcess: ([DetectedSpan], String) -> [DetectedSpan],
        printDiagnostics: (PatternMatcher.Diagnostics, [DetectedSpan], String) -> Void
    ) -> Result<[DetectedSpan], Error> {
        do {
            let entities = try model.extractPII(text, confidenceThreshold: 0.4, useSmartMerging: false)
            let modelSpans = entities.map { entity in
                DetectedSpan(
                    category: entity.label,
                    text: entity.text,
                    start: entity.start,
                    end: entity.end,
                    confidence: entity.confidence,
                    source: .model
                )
            }
            let patternDetection = PatternMatcher.detectWithDiagnostics(text)
            let mergedSpans = modelSpans + patternDetection.spans + supplementalSpans(text)
            let postProcessed = postProcess(mergedSpans, text)
            printDiagnostics(patternDetection.diagnostics, postProcessed, text)
            return .success(postProcessed)
        } catch {
            return .failure(error)
        }
    }

    nonisolated static func visiblePatternDiagnostics(
        for text: String,
        postProcess: ([DetectedSpan], String) -> [DetectedSpan],
        diagnosticsLines: (PatternMatcher.Diagnostics, [DetectedSpan], String) -> [String]
    ) -> [String] {
        let detection = PatternMatcher.detectWithDiagnostics(text)
        let postProcessed = postProcess(detection.spans, text)
        return diagnosticsLines(detection.diagnostics, postProcessed, text)
    }

    nonisolated static func postProcessSpans(_ spans: [DetectedSpan], in text: String) -> [DetectedSpan] {
        let sanitized = PIIDetectorSpanSanitizationSupport.sanitizeSpans(spans)
        let deduplicated = PIIDetectorSpanSanitizationSupport.deduplicateExactSpans(sanitized)
        let merged = PIIDetectorSpanSanitizationSupport.mergeEquivalentSpans(deduplicated)
        let withoutConjoinedFragments = PIIDetectorSpanSanitizationSupport.suppressConjoinedNameFragments(merged)
        let withoutLeadingAddressTails = PIIDetectorSpanSanitizationSupport.suppressLeadingConjunctionAddressSpans(withoutConjoinedFragments)
        let withoutLegalBoilerplate = PIIDetectorSpanSanitizationSupport.suppressLegalBoilerplateFalsePositives(
            withoutLeadingAddressTails,
            in: text
        )
        return PIIDetectorSpanSanitizationSupport.suppressContainedCustomIdentifierSpans(withoutLegalBoilerplate)
    }

    nonisolated static func patternDiagnosticsLines(
        _ diagnostics: PatternMatcher.Diagnostics,
        postProcessed: [DetectedSpan],
        in text: String
    ) -> [String] {
        PIIDetectorPatternDiagnosticsSupport.patternDiagnosticsLines(
            diagnostics,
            postProcessed: postProcessed,
            in: text
        )
    }
}

extension PIIDetector {
    nonisolated static func visiblePatternDiagnostics(for text: String) -> [String] {
        PIIDetectorInferenceSupport.visiblePatternDiagnostics(
            for: text,
            postProcess: PIIDetectorInferenceSupport.postProcessSpans(_:in:),
            diagnosticsLines: PIIDetectorInferenceSupport.patternDiagnosticsLines(_:postProcessed:in:)
        )
    }
}

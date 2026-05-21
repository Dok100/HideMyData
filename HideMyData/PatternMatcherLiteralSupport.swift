import Foundation

nonisolated enum PatternMatcherDetectionSupport {
    struct RuntimePattern {
        let id: String
        let category: String
        let source: Source

        enum Source {
            case regex(NSRegularExpression)
            case literal(String)
        }
    }

    static func loadBuiltinPatterns() -> [RuntimePattern] {
        PatternMatcherBuiltinSupport.loadCompiledBuiltinPatterns().map { pattern in
            RuntimePattern(id: pattern.id, category: pattern.category, source: .regex(pattern.regex))
        }
    }

    static func loadCustomPatterns() -> [RuntimePattern] {
        PatternMatcherLiteralSupport.loadCustomPatternDescriptors().map {
            RuntimePattern(id: $0.label, category: $0.category, source: .literal($0.value))
        }
    }

    static func detectWithDiagnostics(
        text: String,
        builtinPatterns: [RuntimePattern]
    ) -> (spans: [DetectedSpan], diagnostics: PatternMatcher.Diagnostics) {
        var spans: [DetectedSpan] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let storageURL = PatternStorePersistenceSupport.storageURL()
        let legacyStorageURL = PatternStorePersistenceSupport.legacyStorageURL()
        let customPatternDescriptors = PatternMatcherLiteralSupport.loadCustomPatternDescriptors()
        let customPatterns = customPatternDescriptors.map {
            RuntimePattern(id: $0.label, category: $0.category, source: .literal($0.value))
        }

        for pattern in builtinPatterns + customPatterns {
            spans.append(contentsOf: detectedSpans(in: text, fullRange: fullRange, pattern: pattern))
        }

        let rawCustomMatches = spans.filter { span in
            guard span.source == .pattern else { return false }
            return containsCustomDescriptorMatch(for: span, descriptors: customPatternDescriptors)
        }

        return (
            spans,
            PatternMatcher.Diagnostics(
                storagePath: storageURL.path,
                storageFileExists: FileManager.default.fileExists(atPath: storageURL.path),
                legacyStoragePath: legacyStorageURL.path,
                legacyStorageFileExists: FileManager.default.fileExists(atPath: legacyStorageURL.path),
                loadedCustomPatterns: customPatternDescriptors,
                rawCustomMatches: rawCustomMatches
            )
        )
    }

    private static func detectedSpans(
        in text: String,
        fullRange: NSRange,
        pattern: RuntimePattern
    ) -> [DetectedSpan] {
        switch pattern.source {
        case .regex(let regex):
            return regexDetectedSpans(in: text, fullRange: fullRange, regex: regex, category: pattern.category)
        case .literal(let literal):
            return literalDetectedSpans(in: text, literal: literal, category: pattern.category)
        }
    }

    private static func regexDetectedSpans(
        in text: String,
        fullRange: NSRange,
        regex: NSRegularExpression,
        category: String
    ) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []
        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, let swiftRange = Range(match.range, in: text) else { return }
            spans.append(
                detectedSpan(
                    in: text,
                    range: swiftRange,
                    category: category,
                    confidence: 0.99
                )
            )
        }
        return spans
    }

    private static func literalDetectedSpans(
        in text: String,
        literal: String,
        category: String
    ) -> [DetectedSpan] {
        PatternMatcherLiteralSupport.literalMatchRanges(in: text, literal: literal).map { range in
            detectedSpan(
                in: text,
                range: range,
                category: category,
                confidence: 1.0
            )
        }
    }

    private static func detectedSpan(
        in text: String,
        range: Range<String.Index>,
        category: String,
        confidence: Float
    ) -> DetectedSpan {
        let matched = String(text[range])
        let charStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let charEnd = text.distance(from: text.startIndex, to: range.upperBound)
        return DetectedSpan(
            category: category,
            text: matched,
            start: charStart,
            end: charEnd,
            confidence: confidence,
            source: .pattern
        )
    }

    private static func containsCustomDescriptorMatch(
        for span: DetectedSpan,
        descriptors: [PatternMatcher.LoadedCustomPattern]
    ) -> Bool {
        descriptors.contains { descriptor in
            descriptor.category == span.category &&
            descriptor.value.compare(span.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

nonisolated enum PatternMatcherLiteralSupport {
    static func loadCustomPatternDescriptors() -> [PatternMatcher.LoadedCustomPattern] {
        var seenKeys: Set<String> = []
        return CustomPatternStore.loadPersistedPatterns().compactMap { spec in
            let trimmed = spec.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let trimmedLabel = spec.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if PatternStoreNormalizationSupport.isGeneratedPatternLabel(trimmedLabel),
               !PatternStoreNormalizationSupport.isUsefulGeneratedPattern(trimmed) {
                return nil
            }

            let key = dedupeKey(value: trimmed, category: spec.category)
            guard seenKeys.insert(key).inserted else { return nil }

            return PatternMatcher.LoadedCustomPattern(
                label: trimmedLabel,
                value: trimmed,
                category: spec.category
            )
        }
    }

    static func literalMatchRanges(in text: String, literal: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: literal, options: [.caseInsensitive], range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        if !ranges.isEmpty {
            return ranges
        }

        let normalizedText = normalizedLiteralSearchText(text)
        let normalizedLiteral = normalizeLiteralSearchString(literal)
        guard !normalizedLiteral.text.isEmpty else { return [] }

        var normalizedRanges: [Range<String.Index>] = []
        var normalizedSearchRange = normalizedText.text.startIndex..<normalizedText.text.endIndex
        while let range = normalizedText.text.range(of: normalizedLiteral.text, options: [], range: normalizedSearchRange) {
            let startOffset = normalizedText.text.distance(from: normalizedText.text.startIndex, to: range.lowerBound)
            let endOffset = normalizedText.text.distance(from: normalizedText.text.startIndex, to: range.upperBound)
            guard startOffset < normalizedText.map.count, endOffset > 0, endOffset <= normalizedText.map.count else {
                normalizedSearchRange = range.upperBound..<normalizedText.text.endIndex
                continue
            }
            let originalStart = text.index(text.startIndex, offsetBy: normalizedText.map[startOffset])
            let originalEnd = text.index(text.startIndex, offsetBy: normalizedText.map[endOffset - 1] + 1)
            normalizedRanges.append(originalStart..<originalEnd)
            normalizedSearchRange = range.upperBound..<normalizedText.text.endIndex
        }
        if !normalizedRanges.isEmpty {
            return normalizedRanges
        }

        let compactText = compactLiteralSearchText(text)
        let compactLiteral = compactLiteralSearchString(literal)
        guard !compactLiteral.text.isEmpty else { return [] }

        var compactRanges: [Range<String.Index>] = []
        var compactSearchRange = compactText.text.startIndex..<compactText.text.endIndex
        while let range = compactText.text.range(of: compactLiteral.text, options: [], range: compactSearchRange) {
            let startOffset = compactText.text.distance(from: compactText.text.startIndex, to: range.lowerBound)
            let endOffset = compactText.text.distance(from: compactText.text.startIndex, to: range.upperBound)
            guard startOffset < compactText.map.count, endOffset > 0, endOffset <= compactText.map.count else {
                compactSearchRange = range.upperBound..<compactText.text.endIndex
                continue
            }
            let originalStart = text.index(text.startIndex, offsetBy: compactText.map[startOffset])
            let originalEnd = text.index(text.startIndex, offsetBy: compactText.map[endOffset - 1] + 1)
            compactRanges.append(originalStart..<originalEnd)
            compactSearchRange = range.upperBound..<compactText.text.endIndex
        }
        return compactRanges
    }

    static func dedupeKey(value: String, category: String) -> String {
        let normalizedValue = compactLiteralSearchString(value).text
        let normalizedCategory = category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(normalizedCategory)::\(normalizedValue)"
    }

    private static func normalizedLiteralSearchText(_ text: String) -> (text: String, map: [Int]) {
        var normalized = ""
        var map: [Int] = []
        var lastWasWhitespace = false
        var index = 0

        for character in text {
            let scalarText = normalizeLiteralSearchString(String(character)).text
            let isWhitespace = scalarText.allSatisfy(\.isWhitespace)

            if isWhitespace {
                if !lastWasWhitespace, !normalized.isEmpty {
                    normalized.append(" ")
                    map.append(index)
                }
                lastWasWhitespace = true
            } else {
                for scalar in scalarText {
                    normalized.append(scalar)
                    map.append(index)
                }
                lastWasWhitespace = false
            }
            index += 1
        }

        while normalized.last?.isWhitespace == true {
            normalized.removeLast()
            map.removeLast()
        }

        return (normalized, map)
    }

    private static func normalizeLiteralSearchString(_ text: String) -> (text: String, map: [Int]) {
        let lowered = text.lowercased()
        let replaced = lowered
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "str.", with: "strasse")
            .replacingOccurrences(of: "str ", with: "strasse ")
        let folded = replaced.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        return (folded, [])
    }

    private static func compactLiteralSearchText(_ text: String) -> (text: String, map: [Int]) {
        var normalized = ""
        var map: [Int] = []
        var index = 0

        for character in text {
            let compact = compactLiteralSearchString(String(character)).text
            for scalar in compact {
                normalized.append(scalar)
                map.append(index)
            }
            index += 1
        }

        return (normalized, map)
    }

    private static func compactLiteralSearchString(_ text: String) -> (text: String, map: [Int]) {
        let normalized = normalizeLiteralSearchString(text).text
        let compact = normalized.filter { $0.isLetter || $0.isNumber }
        return (compact, [])
    }
}

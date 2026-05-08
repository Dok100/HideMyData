import Foundation

struct CustomPattern: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var value: String
    var category: String

    init(id: UUID = UUID(), label: String, value: String, category: String = "custom_identifier") {
        self.id = id
        self.label = label
        self.value = value
        self.category = category
    }
}

@Observable
@MainActor
final class CustomPatternStore {
    private(set) var patterns: [CustomPattern] = []

    init() {
        load()
    }

    func add(label: String, value: String, category: String = "custom_identifier") {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return }
        for pattern in previewPatterns(label: trimmedLabel, value: trimmedValue, category: category) {
            patterns.append(pattern)
        }
        persist()
    }

    func remove(id: UUID) {
        patterns.removeAll { $0.id == id }
        persist()
    }

    func importPatterns(_ importedPatterns: [CustomPattern], replaceExisting: Bool = false) -> Int {
        let normalizedImportedPatterns = normalizedImportedPatterns(from: importedPatterns)
        guard !normalizedImportedPatterns.isEmpty else { return 0 }

        if replaceExisting {
            patterns = normalizedImportedPatterns
            persist()
            return normalizedImportedPatterns.count
        }

        let existingKeys = Set(patterns.map(patternKey))
        let newPatterns = normalizedImportedPatterns.filter { !existingKeys.contains(patternKey($0)) }
        guard !newPatterns.isEmpty else { return 0 }
        patterns.append(contentsOf: newPatterns)
        persist()
        return newPatterns.count
    }

    func deduplicatePatterns() -> Int {
        let originalCount = patterns.count
        patterns = deduplicated(patterns)
        let removedCount = originalCount - patterns.count
        if removedCount > 0 {
            persist()
        }
        return removedCount
    }

    func migrateLegacyPatterns() -> Int {
        let originalCount = patterns.count
        var rebuilt: [CustomPattern] = []

        for pattern in patterns {
            let normalizedPattern = normalize(pattern)
            guard let normalizedPattern else { continue }

            if isGeneratedPatternLabel(normalizedPattern.label) {
                rebuilt.append(normalizedPattern)
            } else {
                rebuilt.append(contentsOf: expandedPatterns(
                    label: normalizedPattern.label,
                    value: normalizedPattern.value,
                    category: normalizedPattern.category
                ))
            }
        }

        patterns = deduplicated(rebuilt)
        let addedCount = max(0, patterns.count - originalCount)
        if patterns.count != originalCount {
            persist()
        } else {
            persist()
        }
        return addedCount
    }

    func exportPatterns() -> [CustomPattern] {
        patterns
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL()),
              let decoded = try? JSONDecoder().decode([CustomPattern].self, from: data)
        else {
            return
        }
        patterns = decoded
    }

    private func persist() {
        let url = Self.storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(patterns) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated fileprivate static func loadPersistedPatterns() -> [CustomPattern] {
        guard let data = try? Data(contentsOf: storageURL()),
              let decoded = try? JSONDecoder().decode([CustomPattern].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func normalizedCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "custom_identifier" : trimmed
    }

    func previewPatterns(label: String, value: String, category: String = "custom_identifier") -> [CustomPattern] {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return [] }

        let normalizedCategory = normalizedCategory(category)
        let expandedPatterns = expandedPatterns(label: trimmedLabel, value: trimmedValue, category: normalizedCategory)
        let existingKeys = Set(patterns.map(patternKey))

        return expandedPatterns.filter { !existingKeys.contains(patternKey($0)) }
    }

    private func expandedPatterns(label: String, value: String, category: String) -> [CustomPattern] {
        var patterns: [CustomPattern] = []
        var seenKeys: Set<String> = []

        func appendPattern(label patternLabel: String, value patternValue: String) {
            let trimmedValue = patternValue.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !trimmedValue.isEmpty else { return }

            let key = patternKey(label: patternLabel, value: trimmedValue, category: category)
            guard seenKeys.insert(key).inserted else { return }

            patterns.append(CustomPattern(label: patternLabel, value: trimmedValue, category: category))
        }

        appendPattern(label: label, value: value)

        let components = splitPatternComponents(value)
        if components.count > 1 {
            for component in components {
                appendPattern(label: "\(label) – Teil", value: component)
            }

            for chunk in adjacentComponentChunks(components) {
                appendPattern(label: "\(label) – Block", value: chunk)
            }
        }

        return patterns
    }

    private func normalizedImportedPatterns(from importedPatterns: [CustomPattern]) -> [CustomPattern] {
        deduplicated(importedPatterns.compactMap(normalize(_:)))
    }

    private func deduplicated(_ patterns: [CustomPattern]) -> [CustomPattern] {
        var seenKeys: Set<String> = []
        var deduplicatedPatterns: [CustomPattern] = []

        for pattern in patterns {
            let key = patternKey(pattern)
            guard seenKeys.insert(key).inserted else { continue }
            deduplicatedPatterns.append(pattern)
        }

        return deduplicatedPatterns
    }

    private func normalize(_ pattern: CustomPattern) -> CustomPattern? {
        let trimmedLabel = pattern.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = pattern.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = normalizedCategory(pattern.category)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return nil }
        return CustomPattern(label: trimmedLabel, value: trimmedValue, category: normalizedCategory)
    }

    private func isGeneratedPatternLabel(_ label: String) -> Bool {
        label.contains(" – Teil") || label.contains(" – Block")
    }

    private func splitPatternComponents(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        return value
            .components(separatedBy: separators)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter(isUsefulComponent)
    }

    private func adjacentComponentChunks(_ components: [String]) -> [String] {
        guard components.count > 1 else { return [] }

        var chunks: [String] = []
        for startIndex in 0..<(components.count - 1) {
            var chunk = components[startIndex]
            for endIndex in (startIndex + 1)..<components.count {
                chunk += " " + components[endIndex]
                if isUsefulComponent(chunk) {
                    chunks.append(chunk)
                }
            }
        }
        return chunks
    }

    private func isUsefulComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.count >= 5 {
            return true
        }

        let digits = trimmed.filter(\.isNumber).count
        return digits >= 4
    }

    private func patternKey(_ pattern: CustomPattern) -> String {
        patternKey(label: pattern.label, value: pattern.value, category: pattern.category)
    }

    private func patternKey(label: String, value: String, category: String) -> String {
        [
            label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            category.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        ].joined(separator: "::")
    }

    nonisolated private static func storageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("HideMyData", isDirectory: true)
            .appendingPathComponent("custom-patterns.json")
    }
}

nonisolated enum PatternMatcher {
    private struct Pattern {
        let id: String
        let category: String
        let source: Source

        enum Source {
            case regex(NSRegularExpression)
            case literal(String)
        }
    }

    private struct Spec: Decodable {
        let id: String
        let description: String
        let category: String
        let regex: String
    }

    private struct Manifest: Decodable {
        let patterns: [Spec]
    }

    private static let builtinPatterns: [Pattern] = loadPatterns()

    private static func loadPatterns() -> [Pattern] {
        guard let url = Bundle.main.url(forResource: "patterns", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            return []
        }
        return manifest.patterns.compactMap { spec in
            guard let re = try? NSRegularExpression(pattern: spec.regex) else {
                print("PatternMatcher: failed to compile pattern '\(spec.id)'")
                return nil
            }
            return Pattern(id: spec.id, category: spec.category, source: .regex(re))
        }
    }

    private static func loadCustomPatterns() -> [Pattern] {
        CustomPatternStore.loadPersistedPatterns().compactMap { spec in
            let trimmed = spec.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Pattern(id: spec.id.uuidString, category: spec.category, source: .literal(trimmed))
        }
    }

    static func detect(_ text: String) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for pattern in builtinPatterns + loadCustomPatterns() {
            switch pattern.source {
            case .regex(let regex):
                regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    guard let match, let swiftRange = Range(match.range, in: text) else { return }
                    let matched = String(text[swiftRange])
                    let charStart = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
                    let charEnd = text.distance(from: text.startIndex, to: swiftRange.upperBound)
                    spans.append(DetectedSpan(
                        category: pattern.category,
                        text: matched,
                        start: charStart,
                        end: charEnd,
                        confidence: 0.99,
                        source: .pattern
                    ))
                }
            case .literal(let literal):
                for range in literalMatchRanges(in: text, literal: literal) {
                    let matched = String(text[range])
                    let charStart = text.distance(from: text.startIndex, to: range.lowerBound)
                    let charEnd = text.distance(from: text.startIndex, to: range.upperBound)
                    spans.append(DetectedSpan(
                        category: pattern.category,
                        text: matched,
                        start: charStart,
                        end: charEnd,
                        confidence: 1.0,
                        source: .pattern
                    ))
                }
            }
        }
        return spans
    }

    private static func literalMatchRanges(in text: String, literal: String) -> [Range<String.Index>] {
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

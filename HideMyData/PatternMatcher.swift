import Foundation

struct CustomPattern: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var value: String
    var category: String

    nonisolated init(id: UUID = UUID(), label: String, value: String, category: String = "custom_identifier") {
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

    func cleanupWeakPatterns() -> Int {
        let originalCount = patterns.count
        patterns = Self.sanitizedPersistedPatterns(patterns)
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
        let sanitized = sanitizedPersistedPatterns(decoded)
        patterns = sanitized
        if sanitized != decoded {
            persist()
        }
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
        return sanitizedPersistedPatterns(decoded)
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

        func appendPattern(label patternLabel: String, value patternValue: String, generated: Bool) {
            let trimmedValue = patternValue.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !trimmedValue.isEmpty else { return }
            if generated && !Self.isUsefulGeneratedPattern(trimmedValue) {
                return
            }

            let key = patternKey(label: patternLabel, value: trimmedValue, category: category)
            guard seenKeys.insert(key).inserted else { return }

            patterns.append(CustomPattern(label: patternLabel, value: trimmedValue, category: category))
        }

        appendPattern(label: label, value: value, generated: false)

        let components = Self.splitPatternComponents(value)
        if components.count > 1 {
            for component in components {
                appendPattern(label: "\(label) – Teil", value: component, generated: true)
            }

            for chunk in Self.adjacentComponentChunks(components) {
                appendPattern(label: "\(label) – Block", value: chunk, generated: true)
            }
        }

        return patterns
    }

    private func normalizedImportedPatterns(from importedPatterns: [CustomPattern]) -> [CustomPattern] {
        deduplicated(importedPatterns.compactMap(normalize(_:)))
    }

    private func sanitizedPersistedPatterns(_ persistedPatterns: [CustomPattern]) -> [CustomPattern] {
        Self.sanitizedPersistedPatterns(persistedPatterns)
    }

    nonisolated fileprivate static func sanitizedPersistedPatterns(_ persistedPatterns: [CustomPattern]) -> [CustomPattern] {
        var bestBySemanticKey: [String: CustomPattern] = [:]
        var order: [String] = []

        for pattern in persistedPatterns {
            guard let normalizedPattern = normalizedPattern(pattern) else { continue }
            if shouldDropPersistedPattern(normalizedPattern) {
                continue
            }

            let semanticKey = semanticPatternKey(normalizedPattern)
            if let existing = bestBySemanticKey[semanticKey] {
                if preferredPattern(normalizedPattern, over: existing) {
                    bestBySemanticKey[semanticKey] = normalizedPattern
                }
                continue
            }

            bestBySemanticKey[semanticKey] = normalizedPattern
            order.append(semanticKey)
        }

        return order.compactMap { bestBySemanticKey[$0] }
    }

    private func deduplicated(_ patterns: [CustomPattern]) -> [CustomPattern] {
        Self.sanitizedPersistedPatterns(patterns)
    }

    private func normalize(_ pattern: CustomPattern) -> CustomPattern? {
        Self.normalizedPattern(pattern, normalizedCategory: normalizedCategory)
    }

    nonisolated private static func normalizedPattern(
        _ pattern: CustomPattern,
        normalizedCategory: ((String) -> String)? = nil
    ) -> CustomPattern? {
        let trimmedLabel = pattern.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = pattern.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = normalizedCategory?(pattern.category)
            ?? defaultNormalizedCategory(pattern.category)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return nil }
        return CustomPattern(label: trimmedLabel, value: trimmedValue, category: normalizedCategory)
    }

    private func isGeneratedPatternLabel(_ label: String) -> Bool {
        Self.isGeneratedPatternLabel(label)
    }

    nonisolated fileprivate static func isGeneratedPatternLabel(_ label: String) -> Bool {
        label.contains(" – Teil") || label.contains(" – Block")
    }

    nonisolated private static func splitPatternComponents(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        return value
            .components(separatedBy: separators)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter(Self.isUsefulComponent)
    }

    nonisolated private static func adjacentComponentChunks(_ components: [String]) -> [String] {
        guard components.count > 1 else { return [] }

        var chunks: [String] = []
        for startIndex in 0..<(components.count - 1) {
            var chunk = components[startIndex]
            for endIndex in (startIndex + 1)..<components.count {
                chunk += " " + components[endIndex]
                let chunkLength = (startIndex...endIndex).count
                guard chunkLength <= 2 else { continue }
                if Self.isUsefulGeneratedPattern(chunk) {
                    chunks.append(chunk)
                }
            }
        }
        return chunks
    }

    nonisolated fileprivate static func isUsefulComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.count >= 5 {
            return true
        }

        let digits = trimmed.filter(\.isNumber).count
        return digits >= 4
    }

    nonisolated fileprivate static func isUsefulGeneratedPattern(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return false }

        if isPostalCity(trimmed) {
            return false
        }

        if Self.looksLikeEmail(trimmed) || Self.looksLikePhoneOrAccount(trimmed) {
            return true
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let alphaWordCount = words.filter { word in
            word.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }.count
        let digitCount = trimmed.filter(\.isNumber).count
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if digitCount > 0 && letterCount == 0 {
            return false
        }

        if words.count == 1 {
            if digitCount >= 4 {
                return false
            }
            return alphaWordCount >= 2
        }

        if words.count == 2 {
            let first = words[0]
            let second = words[1]
            if Self.isLikelyPostalCity(first: first, second: second) {
                return false
            }
            if Self.isLikelyPersonName(first: first, second: second) {
                return true
            }
            if Self.containsStreetIndicator(trimmed) {
                return true
            }
        }

        if Self.containsStreetIndicator(trimmed) {
            return true
        }

        return alphaWordCount >= 2 && (words.count >= 3 || digitCount > 0)
    }

    nonisolated private static func shouldDropPersistedPattern(_ pattern: CustomPattern) -> Bool {
        if isGeneratedPatternLabel(pattern.label) {
            return !isUsefulGeneratedPattern(pattern.value)
        }

        guard pattern.category == "custom_identifier" else { return false }
        return isWeakOriginalCustomIdentifier(label: pattern.label, value: pattern.value)
    }

    nonisolated private static func isWeakOriginalCustomIdentifier(label: String, value: String) -> Bool {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return true }

        let foldedLabel = trimmedLabel.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let genericLabelFragments = [
            "ort", "stadt", "wohnort", "postleitzahl", "plz", "nachname", "vorname"
        ]

        if genericLabelFragments.contains(where: { foldedLabel == $0 || foldedLabel.hasPrefix($0 + " ") }) {
            return true
        }

        let words = trimmedValue.split(whereSeparator: \.isWhitespace).map(String.init)
        let digitCount = trimmedValue.filter(\.isNumber).count

        if digitCount > 0 && trimmedValue.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return true
        }

        if words.count == 1 {
            if isPostalCity(trimmedValue) {
                return true
            }
            if looksLikeNameToken(trimmedValue) {
                return true
            }
        }

        if words.count <= 2 && isPostalCity(trimmedValue) {
            return true
        }

        return false
    }

    nonisolated private static func looksLikeEmail(_ value: String) -> Bool {
        value.contains("@")
    }

    nonisolated private static func looksLikePhoneOrAccount(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "+-/(). ").union(.decimalDigits)
        let scalars = value.unicodeScalars
        let hasDigits = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let onlyAllowed = scalars.allSatisfy { allowed.contains($0) }
        return hasDigits && onlyAllowed
    }

    nonisolated private static func isLikelyPostalCity(first: String, second: String) -> Bool {
        let firstDigits = first.filter(\.isNumber)
        guard firstDigits.count >= 4, firstDigits.count == first.count else { return false }
        return second.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    nonisolated private static func isPostalCity(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:D\s*-\s*)?\d{4,5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func isLikelyPersonName(first: String, second: String) -> Bool {
        guard !Self.containsStreetIndicator(first), !Self.containsStreetIndicator(second) else { return false }
        return Self.looksLikeNameToken(first) && Self.looksLikeNameToken(second)
    }

    nonisolated private static func looksLikeNameToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.count >= 2 else { return false }
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        return !trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
    }

    nonisolated fileprivate static func containsStreetIndicator(_ value: String) -> Bool {
        let normalized = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let indicators = [
            "strasse", "straße", "str.", "str ", "weg", "allee", "platz", "gasse",
            "ring", "ufer", "chaussee", "steig", "steige"
        ]
        return indicators.contains { normalized.contains($0) }
    }

    nonisolated private static func defaultNormalizedCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "custom_identifier" : trimmed
    }

    nonisolated private static func semanticPatternKey(_ pattern: CustomPattern) -> String {
        let normalizedValue = pattern.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedCategory = pattern.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(normalizedCategory)::\(normalizedValue)"
    }

    nonisolated private static func preferredPattern(_ lhs: CustomPattern, over rhs: CustomPattern) -> Bool {
        let lhsGenerated = isGeneratedPatternLabel(lhs.label)
        let rhsGenerated = isGeneratedPatternLabel(rhs.label)

        if lhsGenerated != rhsGenerated {
            return rhsGenerated
        }

        let lhsIsOriginal = !lhs.label.contains(" – ")
        let rhsIsOriginal = !rhs.label.contains(" – ")
        if lhsIsOriginal != rhsIsOriginal {
            return lhsIsOriginal
        }

        return lhs.label.count < rhs.label.count
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

    nonisolated fileprivate static func storageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateLegacyStorageIfNeeded(base: support)
        return support
            .appendingPathComponent("Inkognito", isDirectory: true)
            .appendingPathComponent("custom-patterns.json")
    }

    nonisolated fileprivate static func legacyStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("HideMyData", isDirectory: true)
            .appendingPathComponent("custom-patterns.json")
    }

    nonisolated private static func migrateLegacyStorageIfNeeded(base: URL) {
        let fm = FileManager.default
        let legacyDir = base.appendingPathComponent("HideMyData", isDirectory: true)
        let newDir = base.appendingPathComponent("Inkognito", isDirectory: true)
        let legacyFile = legacyDir.appendingPathComponent("custom-patterns.json")
        let newFile = newDir.appendingPathComponent("custom-patterns.json")

        guard fm.fileExists(atPath: legacyFile.path),
              !fm.fileExists(atPath: newFile.path) else { return }

        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: legacyFile, to: newFile)
    }
}

nonisolated enum PatternMatcher {
    struct LoadedCustomPattern: Sendable {
        let label: String
        let value: String
        let category: String
    }

    struct Diagnostics: Sendable {
        let storagePath: String
        let storageFileExists: Bool
        let legacyStoragePath: String
        let legacyStorageFileExists: Bool
        let loadedCustomPatterns: [LoadedCustomPattern]
        let rawCustomMatches: [DetectedSpan]
    }

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
        loadCustomPatternDescriptors().map {
            Pattern(id: $0.label, category: $0.category, source: .literal($0.value))
        }
    }

    private static func loadCustomPatternDescriptors() -> [LoadedCustomPattern] {
        var seenKeys: Set<String> = []
        return CustomPatternStore.loadPersistedPatterns().compactMap { spec in
            let trimmed = spec.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let trimmedLabel = spec.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if isGeneratedPatternLabel(trimmedLabel), !CustomPatternStore.isUsefulGeneratedPattern(trimmed) {
                return nil
            }

            let key = dedupeKey(value: trimmed, category: spec.category)
            guard seenKeys.insert(key).inserted else { return nil }

            return LoadedCustomPattern(
                label: trimmedLabel,
                value: trimmed,
                category: spec.category
            )
        }
    }

    static func detect(_ text: String) -> [DetectedSpan] {
        detectWithDiagnostics(text).spans
    }

    static func detectWithDiagnostics(_ text: String) -> (spans: [DetectedSpan], diagnostics: Diagnostics) {
        var spans: [DetectedSpan] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let storageURL = CustomPatternStore.storageURL()
        let legacyStorageURL = CustomPatternStore.legacyStorageURL()
        let customPatternDescriptors = loadCustomPatternDescriptors()
        let customPatterns = customPatternDescriptors.map {
            Pattern(id: $0.label, category: $0.category, source: .literal($0.value))
        }

        for pattern in builtinPatterns + customPatterns {
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
        let rawCustomMatches = spans.filter { span in
            span.source == .pattern && customPatternDescriptors.contains { descriptor in
                descriptor.category == span.category &&
                descriptor.value.compare(span.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        return (
            spans,
            Diagnostics(
                storagePath: storageURL.path,
                storageFileExists: FileManager.default.fileExists(atPath: storageURL.path),
                legacyStoragePath: legacyStorageURL.path,
                legacyStorageFileExists: FileManager.default.fileExists(atPath: legacyStorageURL.path),
                loadedCustomPatterns: customPatternDescriptors,
                rawCustomMatches: rawCustomMatches
            )
        )
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

    private static func isGeneratedPatternLabel(_ label: String) -> Bool {
        label.contains(" – Teil") || label.contains(" – Block")
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

    private static func dedupeKey(value: String, category: String) -> String {
        let normalizedValue = compactLiteralSearchString(value).text
        let normalizedCategory = category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(normalizedCategory)::\(normalizedValue)"
    }
}

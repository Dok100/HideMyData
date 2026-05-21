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
    struct PatternGroup: Identifiable, Equatable {
        let id: String
        let baseLabel: String
        let category: String
        let original: CustomPattern?
        let patterns: [CustomPattern]

        var title: String {
            original?.label ?? baseLabel
        }

        var editorPattern: CustomPattern {
            original ?? patterns[0]
        }

        var componentCount: Int {
            let source = (original?.value ?? patterns[0].value)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return max(source.count, 1)
        }

        var derivedPatterns: [CustomPattern] {
            patterns.filter { $0.id != original?.id }
        }
    }

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

    func remove(ids: [UUID]) {
        let idSet = Set(ids)
        patterns.removeAll { idSet.contains($0.id) }
        persist()
    }

    func update(id: UUID, label: String, value: String, category: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return }
        guard let index = patterns.firstIndex(where: { $0.id == id }) else { return }
        guard let normalized = normalize(CustomPattern(id: id, label: trimmedLabel, value: trimmedValue, category: category)) else { return }
        patterns[index] = normalized
        patterns = deduplicated(patterns)
        persist()
    }

    func replaceGroup(ids: [UUID], label: String, value: String, category: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return }
        let normalizedCategory = normalizedCategory(category)

        let idSet = Set(ids)
        patterns.removeAll { idSet.contains($0.id) }
        patterns.append(contentsOf: expandedPatterns(label: trimmedLabel, value: trimmedValue, category: normalizedCategory))
        patterns = deduplicated(patterns)
        persist()
    }

    func importPatterns(_ importedPatterns: [CustomPattern], replaceExisting: Bool = false) -> Int {
        let result = PatternStoreManagementSupport.importedPatterns(
            currentPatterns: patterns,
            importedPatterns: importedPatterns,
            replaceExisting: replaceExisting,
            normalizedImportedPatterns: normalizedImportedPatterns(from:),
            patternKey: patternKey(_:)
        )
        guard result.importedCount > 0 else { return 0 }
        patterns = result.patterns
        persist()
        return result.importedCount
    }

    func deduplicatePatterns() -> Int {
        let result = PatternStoreManagementSupport.deduplicatedPatterns(
            currentPatterns: patterns,
            deduplicated: deduplicated(_:)
        )
        guard result.removedCount > 0 else { return 0 }
        patterns = result.patterns
        persist()
        return result.removedCount
    }

    func previewDeduplicateRemovalCount() -> Int {
        patterns.count - deduplicated(patterns).count
    }

    func cleanupWeakPatterns() -> Int {
        let result = PatternStoreManagementSupport.cleanedWeakPatterns(
            currentPatterns: patterns,
            sanitizedPersistedPatterns: Self.sanitizedPersistedPatterns(_:)
        )
        guard result.removedCount > 0 else { return 0 }
        patterns = result.patterns
        persist()
        return result.removedCount
    }

    func previewWeakPatternRemovalCount() -> Int {
        patterns.count - Self.sanitizedPersistedPatterns(patterns).count
    }

    func migrateLegacyPatterns() -> Int {
        let result = PatternStoreManagementSupport.migratedLegacyPatterns(
            currentPatterns: patterns,
            normalize: normalize(_:) ,
            isGeneratedPatternLabel: isGeneratedPatternLabel(_:),
            expandedPatterns: { label, value, category in
                expandedPatterns(label: label, value: value, category: category)
            },
            deduplicated: deduplicated(_:)
        )
        patterns = result.patterns
        persist()
        return result.addedCount
    }

    func previewLegacyMigrationAddedCount() -> Int {
        PatternStoreManagementSupport.migratedLegacyPatterns(
            currentPatterns: patterns,
            normalize: normalize(_:) ,
            isGeneratedPatternLabel: isGeneratedPatternLabel(_:),
            expandedPatterns: { label, value, category in
                expandedPatterns(label: label, value: value, category: category)
            },
            deduplicated: deduplicated(_:)
        ).addedCount
    }

    func exportPatterns() -> [CustomPattern] {
        patterns
    }

    func groupedPatterns() -> [PatternGroup] {
        PatternStoreManagementSupport.groupedPatterns(
            patterns: patterns,
            isGeneratedPatternLabel: Self.isGeneratedPatternLabel(_:),
            expandedPatterns: { label, value, category in
                expandedPatterns(label: label, value: value, category: category)
            },
            patternKey: patternKey(_:) ,
            groupID: { baseLabel, category, anchorID in
                groupID(baseLabel: baseLabel, category: category, anchorID: anchorID)
            },
            baseLabel: Self.baseLabel(for:),
            sortGroupPatterns: sortGroupPatterns(_:)
        )
    }

    private func load() {
        guard let decoded = PatternStorePersistenceSupport.loadDecodedPatterns() else { return }
        let sanitized = sanitizedPersistedPatterns(decoded)
        patterns = sanitized
        if sanitized != decoded {
            persist()
        }
    }

    private func persist() {
        PatternStorePersistenceSupport.persist(patterns)
    }

    nonisolated static func loadPersistedPatterns() -> [CustomPattern] {
        PatternStorePersistenceSupport.loadPatterns()
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

    nonisolated static func sanitizedPersistedPatterns(_ persistedPatterns: [CustomPattern]) -> [CustomPattern] {
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

    private func baseLabel(for label: String) -> String {
        Self.baseLabel(for: label)
    }

    nonisolated fileprivate static func baseLabel(for label: String) -> String {
        label
            .replacingOccurrences(of: " – Teil", with: "")
            .replacingOccurrences(of: " – Block", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func groupID(baseLabel: String, category: String, anchorID: UUID) -> String {
        [
            baseLabel.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            category.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            anchorID.uuidString
        ].joined(separator: "::")
    }

    private func sortGroupPatterns(_ patterns: [CustomPattern]) -> [CustomPattern] {
        patterns.sorted { lhs, rhs in
            let lhsGenerated = Self.isGeneratedPatternLabel(lhs.label)
            let rhsGenerated = Self.isGeneratedPatternLabel(rhs.label)
            if lhsGenerated != rhsGenerated {
                return !lhsGenerated
            }
            let lhsBlock = lhs.label.contains(" – Block")
            let rhsBlock = rhs.label.contains(" – Block")
            if lhsBlock != rhsBlock {
                return !lhsBlock
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
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

    nonisolated static func isUsefulGeneratedPattern(_ value: String) -> Bool {
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

    private static let builtinPatterns: [Pattern] = loadPatterns()

    private static func loadPatterns() -> [Pattern] {
        PatternMatcherBuiltinSupport.loadCompiledBuiltinPatterns().map { pattern in
            Pattern(id: pattern.id, category: pattern.category, source: .regex(pattern.regex))
        }
    }

    private static func loadCustomPatterns() -> [Pattern] {
        loadCustomPatternDescriptors().map {
            Pattern(id: $0.label, category: $0.category, source: .literal($0.value))
        }
    }

    private static func loadCustomPatternDescriptors() -> [LoadedCustomPattern] {
        PatternMatcherLiteralSupport.loadCustomPatternDescriptors()
    }

    static func detect(_ text: String) -> [DetectedSpan] {
        detectWithDiagnostics(text).spans
    }

    static func detectWithDiagnostics(_ text: String) -> (spans: [DetectedSpan], diagnostics: Diagnostics) {
        var spans: [DetectedSpan] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let storageURL = PatternStorePersistenceSupport.storageURL()
        let legacyStorageURL = PatternStorePersistenceSupport.legacyStorageURL()
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
                for range in PatternMatcherLiteralSupport.literalMatchRanges(in: text, literal: literal) {
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
}

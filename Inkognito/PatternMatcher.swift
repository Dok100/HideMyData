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
    struct PreviewPatternStatus: Identifiable, Equatable {
        let pattern: CustomPattern
        let isExisting: Bool

        var id: UUID { pattern.id }
    }

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
        let sanitized = Self.sanitizedPersistedPatterns(decoded)
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
        PatternStoreNormalizationSupport.normalizedCategory(category)
    }

    func previewPatterns(label: String, value: String, category: String = "custom_identifier") -> [CustomPattern] {
        previewPatternStatuses(label: label, value: value, category: category)
            .filter { !$0.isExisting }
            .map(\.pattern)
    }

    func previewPatternStatuses(label: String, value: String, category: String = "custom_identifier") -> [PreviewPatternStatus] {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return [] }

        let normalizedCategory = normalizedCategory(category)
        let expanded = expandedPatterns(label: trimmedLabel, value: trimmedValue, category: normalizedCategory)
        let existingKeys = Set(patterns.map(patternKey))

        return expanded.map { pattern in
            PreviewPatternStatus(
                pattern: pattern,
                isExisting: existingKeys.contains(patternKey(pattern))
            )
        }
    }

    private func expandedPatterns(label: String, value: String, category: String) -> [CustomPattern] {
        PatternStoreNormalizationSupport.expandedPatterns(label: label, value: value, category: category)
    }

    private func normalizedImportedPatterns(from importedPatterns: [CustomPattern]) -> [CustomPattern] {
        deduplicated(importedPatterns.compactMap(normalize(_:)))
    }

    nonisolated static func sanitizedPersistedPatterns(_ persistedPatterns: [CustomPattern]) -> [CustomPattern] {
        PatternStoreNormalizationSupport.sanitizedPersistedPatterns(persistedPatterns)
    }

    private func deduplicated(_ patterns: [CustomPattern]) -> [CustomPattern] {
        Self.sanitizedPersistedPatterns(patterns)
    }

    nonisolated fileprivate static func baseLabel(for label: String) -> String {
        PatternStoreNormalizationSupport.baseLabel(for: label)
    }

    private func groupID(baseLabel: String, category: String, anchorID: UUID) -> String {
        [
            baseLabel.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            category.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            anchorID.uuidString
        ].joined(separator: "::")
    }

    private func sortGroupPatterns(_ patterns: [CustomPattern]) -> [CustomPattern] {
        PatternStoreNormalizationSupport.sortGroupPatterns(patterns)
    }

    private func normalize(_ pattern: CustomPattern) -> CustomPattern? {
        Self.normalizedPattern(pattern, normalizedCategory: normalizedCategory)
    }

    nonisolated private static func normalizedPattern(
        _ pattern: CustomPattern,
        normalizedCategory: ((String) -> String)? = nil
    ) -> CustomPattern? {
        PatternStoreNormalizationSupport.normalizedPattern(pattern, normalizedCategory: normalizedCategory)
    }

    private func isGeneratedPatternLabel(_ label: String) -> Bool {
        Self.isGeneratedPatternLabel(label)
    }

    nonisolated fileprivate static func isGeneratedPatternLabel(_ label: String) -> Bool {
        PatternStoreNormalizationSupport.isGeneratedPatternLabel(label)
    }

    nonisolated static func isUsefulGeneratedPattern(_ value: String) -> Bool {
        PatternStoreNormalizationSupport.isUsefulGeneratedPattern(value)
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

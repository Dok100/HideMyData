import Foundation

nonisolated enum PatternStoreManagementSupport {
    static func importedPatterns(
        currentPatterns: [CustomPattern],
        importedPatterns: [CustomPattern],
        replaceExisting: Bool,
        normalizedImportedPatterns: ([CustomPattern]) -> [CustomPattern],
        patternKey: (CustomPattern) -> String
    ) -> (patterns: [CustomPattern], importedCount: Int) {
        let normalizedImportedPatterns = normalizedImportedPatterns(importedPatterns)
        guard !normalizedImportedPatterns.isEmpty else {
            return (currentPatterns, 0)
        }

        if replaceExisting {
            return (normalizedImportedPatterns, normalizedImportedPatterns.count)
        }

        let existingKeys = Set(currentPatterns.map(patternKey))
        let newPatterns = normalizedImportedPatterns.filter { !existingKeys.contains(patternKey($0)) }
        guard !newPatterns.isEmpty else {
            return (currentPatterns, 0)
        }

        return (currentPatterns + newPatterns, newPatterns.count)
    }

    static func deduplicatedPatterns(
        currentPatterns: [CustomPattern],
        deduplicated: ([CustomPattern]) -> [CustomPattern]
    ) -> (patterns: [CustomPattern], removedCount: Int) {
        let updatedPatterns = deduplicated(currentPatterns)
        return (updatedPatterns, currentPatterns.count - updatedPatterns.count)
    }

    static func cleanedWeakPatterns(
        currentPatterns: [CustomPattern],
        sanitizedPersistedPatterns: ([CustomPattern]) -> [CustomPattern]
    ) -> (patterns: [CustomPattern], removedCount: Int) {
        let updatedPatterns = sanitizedPersistedPatterns(currentPatterns)
        return (updatedPatterns, currentPatterns.count - updatedPatterns.count)
    }

    static func migratedLegacyPatterns(
        currentPatterns: [CustomPattern],
        normalize: (CustomPattern) -> CustomPattern?,
        isGeneratedPatternLabel: (String) -> Bool,
        expandedPatterns: (String, String, String) -> [CustomPattern],
        deduplicated: ([CustomPattern]) -> [CustomPattern]
    ) -> (patterns: [CustomPattern], addedCount: Int) {
        var rebuilt: [CustomPattern] = []

        for pattern in currentPatterns {
            guard let normalizedPattern = normalize(pattern) else { continue }

            if isGeneratedPatternLabel(normalizedPattern.label) {
                rebuilt.append(normalizedPattern)
            } else {
                rebuilt.append(contentsOf: expandedPatterns(
                    normalizedPattern.label,
                    normalizedPattern.value,
                    normalizedPattern.category
                ))
            }
        }

        let updatedPatterns = deduplicated(rebuilt)
        return (updatedPatterns, max(0, updatedPatterns.count - currentPatterns.count))
    }

    static func groupedPatterns(
        patterns: [CustomPattern],
        isGeneratedPatternLabel: (String) -> Bool,
        expandedPatterns: (String, String, String) -> [CustomPattern],
        patternKey: (CustomPattern) -> String,
        groupID: (String, String, UUID) -> String,
        baseLabel: (String) -> String,
        sortGroupPatterns: ([CustomPattern]) -> [CustomPattern]
    ) -> [CustomPatternStore.PatternGroup] {
        let originals = patterns.filter { !isGeneratedPatternLabel($0.label) }
        var remaining = Dictionary(uniqueKeysWithValues: patterns.map { ($0.id, $0) })
        var groups: [CustomPatternStore.PatternGroup] = []

        for original in originals {
            let expected = expandedPatterns(original.label, original.value, original.category)
            var matched: [CustomPattern] = []

            for pattern in expected {
                if let match = remaining.values.first(where: { patternKey($0) == patternKey(pattern) }) {
                    matched.append(match)
                    remaining.removeValue(forKey: match.id)
                }
            }

            if matched.isEmpty, let fallback = remaining.removeValue(forKey: original.id) {
                matched = [fallback]
            }

            guard !matched.isEmpty else { continue }

            groups.append(
                CustomPatternStore.PatternGroup(
                    id: groupID(baseLabel(original.label), original.category, original.id),
                    baseLabel: baseLabel(original.label),
                    category: original.category,
                    original: matched.first(where: { $0.id == original.id }) ?? original,
                    patterns: sortGroupPatterns(matched)
                )
            )
        }

        let orphanGroups = Dictionary(grouping: remaining.values) { pattern in
            groupID(baseLabel(pattern.label), pattern.category, pattern.id)
        }
        .values
        .map { orphanPatterns in
            let sorted = sortGroupPatterns(Array(orphanPatterns))
            let first = sorted[0]
            return CustomPatternStore.PatternGroup(
                id: groupID(baseLabel(first.label), first.category, first.id),
                baseLabel: baseLabel(first.label),
                category: first.category,
                original: sorted.first(where: { !isGeneratedPatternLabel($0.label) }),
                patterns: sorted
            )
        }
        .sorted { (lhs: CustomPatternStore.PatternGroup, rhs: CustomPatternStore.PatternGroup) in
            let lhsTitle = lhs.original?.label ?? lhs.baseLabel
            let rhsTitle = rhs.original?.label ?? rhs.baseLabel
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }

        groups.append(contentsOf: orphanGroups)
        return groups
    }
}

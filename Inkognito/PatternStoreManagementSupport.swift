import Foundation

nonisolated enum PatternStoreNormalizationSupport {
    static func normalizedCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "custom_identifier" : trimmed
    }

    static func previewPatterns(
        currentPatterns: [CustomPattern],
        label: String,
        value: String,
        category: String
    ) -> [CustomPattern] {
        let normalizedCategory = normalizedCategory(category)
        let expandedPatterns = expandedPatterns(label: label, value: value, category: normalizedCategory)
        let existingKeys = Set(currentPatterns.map(patternKey))
        return expandedPatterns.filter { !existingKeys.contains(patternKey($0)) }
    }

    static func expandedPatterns(label: String, value: String, category: String) -> [CustomPattern] {
        var patterns: [CustomPattern] = []
        var seenKeys: Set<String> = []

        func appendPattern(label patternLabel: String, value patternValue: String, generated: Bool) {
            let trimmedValue = patternValue.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !trimmedValue.isEmpty else { return }
            if generated && !isUsefulGeneratedPattern(trimmedValue) {
                return
            }

            let key = patternKey(label: patternLabel, value: trimmedValue, category: category)
            guard seenKeys.insert(key).inserted else { return }

            patterns.append(CustomPattern(label: patternLabel, value: trimmedValue, category: category))
        }

        appendPattern(label: label, value: value, generated: false)

        let components = splitPatternComponents(value)
        if components.count > 1 {
            for component in components {
                appendPattern(label: "\(label) – Teil", value: component, generated: true)
            }

            for chunk in adjacentComponentChunks(components) {
                appendPattern(label: "\(label) – Block", value: chunk, generated: true)
            }
        }

        return patterns
    }

    static func sanitizedPersistedPatterns(_ persistedPatterns: [CustomPattern]) -> [CustomPattern] {
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

    static func baseLabel(for label: String) -> String {
        label
            .replacingOccurrences(of: " – Teil", with: "")
            .replacingOccurrences(of: " – Block", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sortGroupPatterns(_ patterns: [CustomPattern]) -> [CustomPattern] {
        patterns.sorted { lhs, rhs in
            let lhsGenerated = isGeneratedPatternLabel(lhs.label)
            let rhsGenerated = isGeneratedPatternLabel(rhs.label)
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

    static func normalizedPattern(
        _ pattern: CustomPattern,
        normalizedCategory: ((String) -> String)? = nil
    ) -> CustomPattern? {
        let trimmedLabel = pattern.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = pattern.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = normalizedCategory?(pattern.category)
            ?? self.normalizedCategory(pattern.category)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { return nil }
        return CustomPattern(label: trimmedLabel, value: trimmedValue, category: normalizedCategory)
    }

    static func isGeneratedPatternLabel(_ label: String) -> Bool {
        label.contains(" – Teil") || label.contains(" – Block")
    }

    static func isUsefulGeneratedPattern(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return false }

        if isPostalCity(trimmed) {
            return false
        }

        if looksLikeEmail(trimmed) || looksLikePhoneOrAccount(trimmed) {
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
            if isLikelyPostalCity(first: first, second: second) {
                return false
            }
            if isLikelyPersonName(first: first, second: second) {
                return true
            }
            if containsStreetIndicator(trimmed) {
                return true
            }
        }

        if containsStreetIndicator(trimmed) {
            return true
        }

        return alphaWordCount >= 2 && (words.count >= 3 || digitCount > 0)
    }

    static func containsStreetIndicator(_ value: String) -> Bool {
        let normalized = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let indicators = [
            "strasse", "straße", "str.", "str ", "weg", "allee", "platz", "gasse",
            "ring", "ufer", "chaussee", "steig", "steige"
        ]
        return indicators.contains { normalized.contains($0) }
    }

    private static func splitPatternComponents(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        return value
            .components(separatedBy: separators)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter(isUsefulComponent)
    }

    private static func adjacentComponentChunks(_ components: [String]) -> [String] {
        guard components.count > 1 else { return [] }

        var chunks: [String] = []
        for startIndex in 0..<(components.count - 1) {
            var chunk = components[startIndex]
            for endIndex in (startIndex + 1)..<components.count {
                chunk += " " + components[endIndex]
                let chunkLength = (startIndex...endIndex).count
                guard chunkLength <= 2 else { continue }
                if isUsefulGeneratedPattern(chunk) {
                    chunks.append(chunk)
                }
            }
        }
        return chunks
    }

    private static func isUsefulComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.count >= 5 {
            return true
        }

        let digits = trimmed.filter(\.isNumber).count
        return digits >= 4
    }

    private static func shouldDropPersistedPattern(_ pattern: CustomPattern) -> Bool {
        if isGeneratedPatternLabel(pattern.label) {
            return !isUsefulGeneratedPattern(pattern.value)
        }

        guard pattern.category == "custom_identifier" else { return false }
        return isWeakOriginalCustomIdentifier(label: pattern.label, value: pattern.value)
    }

    private static func isWeakOriginalCustomIdentifier(label: String, value: String) -> Bool {
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

    private static func looksLikeEmail(_ value: String) -> Bool {
        value.contains("@")
    }

    private static func looksLikePhoneOrAccount(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "+-/(). ").union(.decimalDigits)
        let scalars = value.unicodeScalars
        let hasDigits = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let onlyAllowed = scalars.allSatisfy { allowed.contains($0) }
        return hasDigits && onlyAllowed
    }

    private static func isLikelyPostalCity(first: String, second: String) -> Bool {
        let firstDigits = first.filter(\.isNumber)
        guard firstDigits.count >= 4, firstDigits.count == first.count else { return false }
        return second.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private static func isPostalCity(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:D\s*-\s*)?\d{4,5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isLikelyPersonName(first: String, second: String) -> Bool {
        guard !containsStreetIndicator(first), !containsStreetIndicator(second) else { return false }
        return looksLikeNameToken(first) && looksLikeNameToken(second)
    }

    private static func looksLikeNameToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.count >= 2 else { return false }
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        return !trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
    }

    private static func semanticPatternKey(_ pattern: CustomPattern) -> String {
        let normalizedValue = pattern.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedCategory = pattern.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(normalizedCategory)::\(normalizedValue)"
    }

    private static func preferredPattern(_ lhs: CustomPattern, over rhs: CustomPattern) -> Bool {
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

    private static func patternKey(_ pattern: CustomPattern) -> String {
        patternKey(label: pattern.label, value: pattern.value, category: pattern.category)
    }

    private static func patternKey(label: String, value: String, category: String) -> String {
        [
            label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            category.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        ].joined(separator: "::")
    }
}

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

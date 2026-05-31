import Foundation

struct OCRContextLineCandidate {
    let lineIndex: Int
    let category: String
    let matchedText: String?
}

enum OCRContextAnalyzer {
    static func looksLikeLabeledFormBlockStart(_ text: String) -> Bool {
        guard let key = DocumentTextHeuristics.standaloneFieldLabelKey(in: text) else { return false }
        return key == "vorname" || key == "name"
    }

    static func labeledAddressBlockCandidates(
        in lines: [String],
        startingAt index: Int,
        allowDotsInCityTokens: Bool,
        includeLabelAsAddress: Bool = true
    ) -> [OCRContextLineCandidate] {
        guard lines.indices.contains(index) else { return [] }

        var candidates: [OCRContextLineCandidate] = []
        if includeLabelAsAddress {
            candidates.append(.init(lineIndex: index, category: "private_address", matchedText: nil))
        }

        let searchEnd = min(lines.count, index + 8)
        var blockIndices: [Int] = []
        var previousComparable = ""
        for cursor in (index + 1)..<searchEnd {
            let cleaned = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            let comparable = cleaned
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
            if comparable == previousComparable, !comparable.isEmpty { continue }

            blockIndices.append(cursor)
            previousComparable = comparable
            if DocumentTextHeuristics.looksLikePostalCityLine(cleaned, allowDotsInCityTokens: allowDotsInCityTokens) {
                break
            }
        }

        guard !blockIndices.isEmpty else { return candidates }

        var dataStart = 0
        if let firstIndex = blockIndices.first, looksLikeHonorificLine(lines[firstIndex]) {
            candidates.append(.init(lineIndex: firstIndex, category: "private_person", matchedText: nil))
            dataStart = 1
        }

        for relativeIndex in dataStart..<blockIndices.count {
            let actualIndex = blockIndices[relativeIndex]
            let cleaned = lines[actualIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if relativeIndex == dataStart {
                candidates.append(.init(lineIndex: actualIndex, category: "private_person", matchedText: nil))
                continue
            }
            if DocumentTextHeuristics.looksLikeGermanStreetLine(cleaned) ||
                DocumentTextHeuristics.looksLikePostalCityLine(cleaned, allowDotsInCityTokens: allowDotsInCityTokens) {
                candidates.append(.init(lineIndex: actualIndex, category: "private_address", matchedText: nil))
            }
        }

        return candidates
    }

    static func labeledFormAddressCandidates(in lines: [String], startingAt index: Int) -> [OCRContextLineCandidate] {
        let fieldOrder = ["vorname", "name", "strasse", "hausnr", "plz", "ort"]
        var labelKeys: [String] = []
        var cursor = index

        while cursor < lines.count,
              let key = DocumentTextHeuristics.standaloneFieldLabelKey(in: lines[cursor]) {
            labelKeys.append(key)
            cursor += 1
        }

        guard !labelKeys.isEmpty else { return [] }

        let orderedKeys = fieldOrder.filter { labelKeys.contains($0) }
        guard !orderedKeys.isEmpty else { return [] }

        var valueIndices: [Int] = []
        var scan = cursor
        while scan < lines.count, valueIndices.count < orderedKeys.count {
            let cleanedLine = lines[scan].trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedLine.isEmpty {
                scan += 1
                continue
            }
            if DocumentTextHeuristics.standaloneFieldLabelKey(in: cleanedLine) != nil {
                break
            }
            valueIndices.append(scan)
            scan += 1
        }

        var candidates: [OCRContextLineCandidate] = []
        for (pairIndex, key) in orderedKeys.enumerated() {
            guard valueIndices.indices.contains(pairIndex) else { continue }
            let valueIndex = valueIndices[pairIndex]
            let valueText = lines[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !valueText.isEmpty else { continue }

            switch key {
            case "vorname", "name":
                candidates.append(.init(lineIndex: valueIndex, category: "private_person", matchedText: nil))
            case "strasse", "hausnr", "plz", "ort":
                candidates.append(.init(lineIndex: valueIndex, category: "private_address", matchedText: nil))
            default:
                break
            }
        }

        return candidates
    }

    static func windowRecipientBlockCandidates(
        in lines: [String],
        nameIndex: Int,
        allowDotsInCityTokens: Bool
    ) -> [OCRContextLineCandidate]? {
        guard lines.indices.contains(nameIndex),
              let recipientBlock = OCRRecipientHeuristics.resolveWindowRecipientBlock(
                in: lines,
                nameIndex: nameIndex,
                allowDotsInCityTokens: allowDotsInCityTokens
              )
        else { return nil }

        var candidates: [OCRContextLineCandidate] = [
            .init(lineIndex: nameIndex, category: "private_person", matchedText: nil)
        ]
        for streetIndex in recipientBlock.streetIndices {
            candidates.append(.init(lineIndex: streetIndex, category: "private_address", matchedText: nil))
        }
        candidates.append(.init(lineIndex: recipientBlock.postalCityIndex, category: "private_address", matchedText: nil))
        return candidates
    }

    static func recoveredWindowRecipientPreludeCandidates(
        in lines: [String],
        searchLimit: Int,
        allowDotsInCityTokens: Bool,
        isLineVisible: (Int) -> Bool
    ) -> [OCRContextLineCandidate] {
        let cappedLimit = min(lines.count, searchLimit)
        guard cappedLimit > 0 else { return [] }

        var recovered: [OCRContextLineCandidate] = []
        for cityIndex in 0..<cappedLimit {
            let cityText = lines[cityIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard DocumentTextHeuristics.looksLikePostalCityLine(cityText, allowDotsInCityTokens: allowDotsInCityTokens),
                  isLineVisible(cityIndex)
            else { continue }

            let nameSearchStart = max(0, cityIndex - 4)
            let possibleNameIndices = Array(nameSearchStart..<cityIndex).filter { index in
                let text = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return DocumentTextHeuristics.looksLikeWindowRecipientNameLine(text) &&
                    OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: index)
            }

            guard let nameIndex = possibleNameIndices.last else { continue }

            let streetIndices = Array((nameIndex + 1)..<cityIndex).filter { index in
                let text = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return DocumentTextHeuristics.looksLikeGermanStreetLine(text)
            }
            guard !streetIndices.isEmpty else { continue }

            if !isLineVisible(nameIndex) {
                recovered.append(.init(lineIndex: nameIndex, category: "private_person", matchedText: nil))
            }
            for streetIndex in streetIndices where !isLineVisible(streetIndex) {
                recovered.append(.init(lineIndex: streetIndex, category: "private_address", matchedText: nil))
            }
        }

        return recovered
    }

    private static func looksLikeHonorificLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

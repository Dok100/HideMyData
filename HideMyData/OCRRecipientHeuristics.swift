import Foundation

struct OCRRecipientBlock {
    let streetIndices: [Int]
    let postalCityIndex: Int
}

enum OCRRecipientHeuristics {
    static func hasNearbyOrganizationHeader(in lines: [String], before index: Int) -> Bool {
        guard index > 0 else { return false }
        let start = max(0, index - 3)
        for previousIndex in start..<index {
            if DocumentTextHeuristics.looksLikeOrganizationHeaderLine(lines[previousIndex]) {
                return true
            }
        }
        return false
    }

    static func resolveWindowRecipientBlock(
        in lines: [String],
        nameIndex: Int,
        allowDotsInCityTokens: Bool
    ) -> OCRRecipientBlock? {
        let searchEnd = min(lines.count, nameIndex + 5)
        guard nameIndex + 1 < searchEnd else { return nil }

        var streetIndices: [Int] = []
        for lineIndex in (nameIndex + 1)..<searchEnd {
            let text = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if DocumentTextHeuristics.looksLikeGermanStreetLine(text) {
                streetIndices.append(lineIndex)
                continue
            }

            if !streetIndices.isEmpty,
               DocumentTextHeuristics.looksLikePostalCityLine(text, allowDotsInCityTokens: allowDotsInCityTokens) {
                return OCRRecipientBlock(streetIndices: streetIndices, postalCityIndex: lineIndex)
            }
        }

        return nil
    }
}

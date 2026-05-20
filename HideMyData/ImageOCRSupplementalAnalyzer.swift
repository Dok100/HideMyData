import CoreGraphics
import Foundation

struct ImageSupplementalOCRCandidate {
    let span: DetectedSpan
    let normalizedRects: [CGRect]
}

enum ImageOCRSupplementalAnalyzer {
    static func analyze(page: OCRPage, modelInput: String) -> (candidates: [ImageSupplementalOCRCandidate], diagnostics: [String]) {
        var candidates: [ImageSupplementalOCRCandidate] = []
        var diagnostics: [String] = []
        let lines = page.lines.map(\.text)

        func appendCandidate(lineIndex: Int, category: String) {
            guard let span = page.lineSpan(at: lineIndex, category: category),
                  let normalizedRect = page.normalizedLineBox(at: lineIndex)
            else { return }

            candidates.append(
                ImageSupplementalOCRCandidate(
                    span: span,
                    normalizedRects: [normalizedRect]
                )
            )
        }

        func appendCandidate(lineIndex: Int, matchedText: String, category: String) {
            guard let match = page.lineMatch(at: lineIndex, matchedText: matchedText, category: category) else { return }
            candidates.append(
                ImageSupplementalOCRCandidate(
                    span: match.span,
                    normalizedRects: [match.rect]
                )
            )
        }

        func appendRecipientBlock(nameIndex: Int, sourceLabel: String) {
            guard let recipientCandidates = OCRContextAnalyzer.windowRecipientBlockCandidates(
                in: lines,
                nameIndex: nameIndex,
                allowDotsInCityTokens: false
            ) else { return }

            let cleanedName = page.lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let streetIndices = recipientCandidates
                .filter { $0.category == "private_address" }
                .dropLast()
                .map(\.lineIndex)
            let postalCityIndex = recipientCandidates.last?.lineIndex ?? nameIndex
            diagnostics.append(
                "Supplemental OCR hit: \(sourceLabel) at line \(nameIndex) -> '\(cleanedName)' | streets='\(streetIndices.map { page.lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " | "))' | city='\(page.lines[postalCityIndex].text.trimmingCharacters(in: .whitespacesAndNewlines))'"
            )
            for candidate in recipientCandidates {
                appendCandidate(lineIndex: candidate.lineIndex, category: candidate.category)
            }
        }

        func appendLabeledFormAddressBlock(startingAt index: Int) {
            var labelLineIndices: [Int] = []
            var cursor = index
            while cursor < lines.count,
                  DocumentTextHeuristics.standaloneFieldLabelKey(in: lines[cursor]) != nil {
                labelLineIndices.append(cursor)
                cursor += 1
            }
            let labelSummary = labelLineIndices.map { page.lines[$0].text }.joined(separator: " | ")
            diagnostics.append("Supplemental OCR hit: labeled form block at line \(index) -> '\(labelSummary)'")
            for candidate in OCRContextAnalyzer.labeledFormAddressCandidates(in: lines, startingAt: index) {
                appendCandidate(lineIndex: candidate.lineIndex, category: candidate.category)
            }
        }

        diagnostics.append("Supplemental OCR candidates: start")
        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if cleaned.localizedCaseInsensitiveContains("Lieferadresse:") ||
                cleaned.localizedCaseInsensitiveContains("Lieferanschrift:") {
                diagnostics.append("Supplemental OCR hit: delivery-address block at line \(index) -> '\(cleaned)'")
                for candidate in OCRContextAnalyzer.labeledAddressBlockCandidates(
                    in: lines,
                    startingAt: index,
                    allowDotsInCityTokens: false
                ) {
                    appendCandidate(lineIndex: candidate.lineIndex, category: candidate.category)
                }
                continue
            }

            if OCRContextAnalyzer.looksLikeLabeledFormBlockStart(cleaned),
               index == 0 || DocumentTextHeuristics.standaloneFieldLabelKey(in: lines[index - 1]) == nil {
                appendLabeledFormAddressBlock(startingAt: index)
                continue
            }

            if let salutationName = DocumentTextHeuristics.salutationPersonName(in: cleaned) {
                diagnostics.append("Supplemental OCR hit: salutation at line \(index) -> '\(salutationName)'")
                appendCandidate(lineIndex: index, matchedText: salutationName, category: "private_person")
                continue
            }

            let looksLikeRecipientName = DocumentTextHeuristics.looksLikeWindowRecipientNameLine(cleaned)
            guard looksLikeRecipientName else { continue }

            let hasHeaderContext = OCRRecipientHeuristics.hasNearbyOrganizationHeader(
                in: lines,
                before: index
            )
            guard hasHeaderContext else { continue }
            appendRecipientBlock(nameIndex: index, sourceLabel: "window recipient block")
        }

        let rawPatternSpans = PatternMatcher.detectWithDiagnostics(modelInput).spans
        for span in rawPatternSpans {
            guard span.category == "custom_identifier",
                  span.confidence >= 0.95,
                  DocumentTextHeuristics.strongCustomIdentifierText(span.text),
                  let lineIndex = page.lineIndex(containing: span.start)
            else { continue }

            guard lineIndex < 12,
                  OCRRecipientHeuristics.hasNearbyOrganizationHeader(in: lines, before: lineIndex)
            else { continue }

            appendRecipientBlock(nameIndex: lineIndex, sourceLabel: "custom recipient fallback")
        }

        if !page.lines.isEmpty {
            let topLines = page.lines.prefix(8).enumerated().map { offset, line in
                let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(offset): \(cleaned)"
            }.joined(separator: " | ")
            diagnostics.append("Supplemental OCR top lines: \(topLines)")
        }

        let deduplicated = deduplicatedCandidates(candidates)
        diagnostics.append("Supplemental OCR candidates: \(deduplicated.count)")
        if deduplicated.isEmpty {
            diagnostics.append("Supplemental OCR candidates detail: <none>")
        } else {
            let detail = deduplicated.map { candidate in
                "[\(candidate.span.category)] \(candidate.span.text)"
            }.joined(separator: " | ")
            diagnostics.append("Supplemental OCR candidates detail: \(detail)")
        }
        return (deduplicated, diagnostics)
    }

    static func recoveredWindowRecipientPreludeCandidates(
        in page: OCRPage,
        searchLimit: Int = 12,
        allowDotsInCityTokens: Bool = false,
        isNormalizedRectVisible: (CGRect) -> Bool
    ) -> [ImageSupplementalOCRCandidate] {
        let lines = page.lines.map(\.text)
        let recoveredCandidates = OCRContextAnalyzer.recoveredWindowRecipientPreludeCandidates(
            in: lines,
            searchLimit: searchLimit,
            allowDotsInCityTokens: allowDotsInCityTokens,
            isLineVisible: { index in
                guard let rect = page.normalizedLineBox(at: index) else { return false }
                return isNormalizedRectVisible(rect)
            }
        )

        return recoveredCandidates.compactMap { candidate in
            guard let rect = page.normalizedLineBox(at: candidate.lineIndex),
                  let span = page.lineSpan(at: candidate.lineIndex, category: candidate.category)
            else { return nil }
            return ImageSupplementalOCRCandidate(span: span, normalizedRects: [rect])
        }
    }

    private static func deduplicatedCandidates(_ candidates: [ImageSupplementalOCRCandidate]) -> [ImageSupplementalOCRCandidate] {
        var unique: [String: ImageSupplementalOCRCandidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            let span = candidate.span
            let key = "\(span.category)::\(span.start)::\(span.end)::\(span.text)"
            if unique[key] == nil {
                order.append(key)
                unique[key] = candidate
            }
        }
        return order.compactMap { unique[$0] }
    }
}

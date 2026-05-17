import Foundation
import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
internal import UniformTypeIdentifiers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@Observable
@MainActor
final class ImageRedactor {
    struct ExportResult {
        let url: URL
        let report: ExportValidationReport
    }

    private struct SupplementalOCRCandidate {
        let span: DetectedSpan
        let rects: [CGRect]
    }

    private struct RedactionEntry {
        let rect: CGRect
        let findingID: UUID?
    }

    enum Phase: Equatable {
        case empty
        case loaded
        case detecting
        case redacted(spanCount: Int, rectCount: Int)
        case saved(URL)
        case failed(String)
    }

    var phase: Phase = .empty
    var image: CGImage?
    var sourceURL: URL?
    var sourceUTI: UTType?
    var redactionStyle: RedactionStyle = .blackRectangle
    var editingMode: EditingMode = .view
    var reviewFindings: [ReviewFinding] = []
    var focusedFindingID: UUID?
    var debugEntries: [DetectionDebugEntry] = []
    var lastExportReport: ExportValidationReport?

    private var sourceImageProperties: [CFString: Any]?
    private var detectionTask: Task<Void, Never>?
    private var redactionEntries: [RedactionEntry] = []
    private var previewEntries: [RedactionEntry] = []
    private var dismissedPreviewEntries: [RedactionEntry] = []

    var statusText: String {
        switch phase {
        case .empty: return "Kein Bild"
        case .loaded:
            if redactionRects.isEmpty && previewRects.isEmpty { return "Geladen" }
            if !previewRects.isEmpty { return "\(previewRects.count) Markierung\(previewRects.count == 1 ? "" : "en")" }
            return "\(redactionRects.count) Schwärzung\(redactionRects.count == 1 ? "" : "en")"
        case .detecting: return "PII wird erkannt…"
        case .redacted(_, let r):
            return "\(r) Bereich\(r == 1 ? "" : "e") vorbereitet"
        case .saved(let url): return "Gespeichert → \(url.lastPathComponent)"
        case .failed(let m): return "Fehler: \(m)"
        }
    }

    var hasRedactions: Bool { !redactionRects.isEmpty }
    var canDetect: Bool { image != nil && phase != .detecting }
    var hasReviewFindings: Bool { !reviewFindings.isEmpty }
    var pendingReviewCount: Int { reviewFindings.filter { $0.status == .pending }.count }
    var hasPendingReview: Bool { pendingReviewCount > 0 }

    var pixelSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    var redactionRects: [CGRect] {
        redactionEntries.map(\.rect)
    }

    var previewRects: [CGRect] {
        previewEntries.map(\.rect)
    }

    var previewRectEntries: [(rect: CGRect, findingID: UUID?)] {
        previewEntries.map { ($0.rect, $0.findingID) }
    }

    // MARK: - Open / Save

    @discardableResult
    func openImage() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return loadImage(from: url)
    }

    @discardableResult
    func loadImage(from url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = normalizedCGImage(from: src) else {
            phase = .failed("Bild konnte nicht geöffnet werden: \(url.lastPathComponent)")
            return false
        }
        let utiString = CGImageSourceGetType(src) as String? ?? ""
        let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        ingest(cg: cg, sourceURL: url, uti: UTType(utiString) ?? .png, properties: properties)
        return true
    }

    @discardableResult
    func loadImage(data: Data, originalURL: URL) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = normalizedCGImage(from: src) else {
            phase = .failed("Bild konnte nicht geöffnet werden: \(originalURL.lastPathComponent)")
            return false
        }
        let utiString = CGImageSourceGetType(src) as String? ?? ""
        let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        ingest(cg: cg, sourceURL: originalURL, uti: UTType(utiString) ?? .png, properties: properties)
        return true
    }

    private func normalizedCGImage(from source: CGImageSource) -> CGImage? {
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard raw != 1, let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return cg
        }
        let ci = CIImage(cgImage: cg).oriented(orientation)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ci, from: ci.extent)
    }

    private func ingest(cg: CGImage, sourceURL: URL, uti: UTType, properties: [CFString: Any]?) {
        cancelDetection()
        self.image = cg
        self.sourceURL = sourceURL
        self.sourceUTI = uti
        self.sourceImageProperties = properties
        self.lastExportReport = nil
        self.redactionEntries = []
        self.previewEntries = []
        clearReviewState()
        self.phase = .loaded
    }

    func save() {
        guard image != nil else { return }
        let outUTI = sourceUTI ?? .png
        let panel = NSSavePanel()
        let exportAccessory = ExportOptionsAccessoryView()
        panel.allowedContentTypes = [outUTI]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedSaveName(uti: outUTI)
        panel.accessoryView = exportAccessory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let exportResult = writeRedacted(to: url, uti: outUTI, options: exportAccessory.options) {
            lastExportReport = exportResult.report
            phase = .saved(exportResult.url)
        } else {
            phase = .failed("Geschwärztes Bild konnte nicht gespeichert werden")
        }
    }

    // MARK: - Detection

    func detectAndRedact(using detector: PIIDetector) {
        cancelDetection()
        detectionTask = Task { [weak self] in
            await self?.runDetection(using: detector)
        }
    }

    func cancelDetection() {
        detectionTask?.cancel()
        detectionTask = nil
    }

    private func runDetection(using detector: PIIDetector) async {
        guard let cg = image else { return }
        redactionEntries.removeAll()
        previewEntries.removeAll()
        clearReviewState()
        phase = .detecting

        guard let ocr = try? await OCREngine.recognize(cg) else {
            phase = .failed("OCR fehlgeschlagen")
            return
        }
        if Task.isCancelled { return }
        if ocr.combinedText.isEmpty {
            phase = .redacted(spanCount: 0, rectCount: 0)
            return
        }

        let (modelInput, offsetMap) = OCRNormalizer.normalize(ocr.combinedText, mode: .ocr)
        let originalCount = ocr.combinedText.count

        let result = await detector.detect(modelInput)
        if Task.isCancelled { return }
        switch result {
        case .failure(let err):
            phase = .failed("Erkennungsfehler: \(err.localizedDescription)")
        case .success(let spans):
            let supplementalAnalysis = supplementalOCRContextAnalysis(in: ocr, modelInput: modelInput)
            let supplementalCandidates = supplementalAnalysis.candidates
            let supplementalSpans = supplementalCandidates.map(\.span)
            let visibleDebugSpans = (spans + supplementalSpans)
                .sorted {
                    if $0.start == $1.start { return $0.end < $1.end }
                    return $0.start < $1.start
                }
            let baseDiagnostics = PIIDetector.visiblePatternDiagnostics(for: modelInput) + supplementalAnalysis.diagnostics
            var reviewCandidates: [ReviewFindingCandidate] = []
            for span in visibleDebugSpans {
                if let supplementalCandidate = supplementalCandidates.first(where: {
                    $0.span.category == span.category &&
                    $0.span.start == span.start &&
                    $0.span.end == span.end &&
                    $0.span.text == span.text
                }) {
                    reviewCandidates.append(
                        ReviewFindingCandidate(
                            category: span.category,
                            snippet: span.text,
                            source: span.source,
                            confidence: span.confidence,
                            pageIndex: nil,
                            rects: supplementalCandidate.rects
                        )
                    )
                    continue
                }

                let (origStart, origEnd) = OCRNormalizer.translateRange(
                    start: span.start, end: span.end, map: offsetMap, originalCount: originalCount
                )
                let normRects = ocr.normalizedBoxes(start: origStart, end: origEnd)
                guard !normRects.isEmpty else { continue }
                reviewCandidates.append(
                    ReviewFindingCandidate(
                        category: span.category,
                        snippet: span.text,
                        source: span.source,
                        confidence: span.confidence,
                        pageIndex: nil,
                        rects: normRects.map { pixelRect(fromNormalized: $0) }
                    )
                )
            }
            let reviewProjections = ReviewFindingCompactor.compact(reviewCandidates)
            for projection in reviewProjections {
                reviewFindings.append(projection.finding)
                for rect in projection.rects {
                    addPreview(rect: rect, findingID: projection.finding.id)
                }
            }
            restoreMissingSupplementalCandidates(supplementalCandidates)
            restoreMissingWindowRecipientPrelude(in: ocr)
            let previewDiagnostics = makePreviewDiagnostics(in: ocr)
            debugEntries = [
                DetectionDebugEntry(
                    title: "Bilddiagnose",
                    textSourceLabel: "Apple Vision OCR",
                    rawText: ocr.combinedText,
                    normalizedText: modelInput,
                    findings: visibleDebugSpans,
                    diagnostics: baseDiagnostics,
                    previewDiagnostics: previewDiagnostics
                )
            ]
            if let firstPending = reviewFindings.first(where: { $0.status == .pending }) {
                selectFinding(firstPending.id)
            }
            phase = .redacted(spanCount: spans.count, rectCount: previewRects.count)
        }
    }

    private func supplementalOCRContextAnalysis(in page: OCRPage, modelInput: String) -> (candidates: [SupplementalOCRCandidate], diagnostics: [String]) {
        var candidates: [SupplementalOCRCandidate] = []
        var diagnostics: [String] = []

        func appendCandidate(lineIndex: Int, category: String) {
            guard let span = page.lineSpan(at: lineIndex, category: category),
                  let normalizedRect = page.normalizedLineBox(at: lineIndex)
            else { return }

            candidates.append(
                SupplementalOCRCandidate(
                    span: span,
                    rects: [pixelRect(fromNormalized: normalizedRect)]
                )
            )
        }

        func appendCandidate(lineIndex: Int, matchedText: String, category: String) {
            guard let match = page.lineMatch(at: lineIndex, matchedText: matchedText, category: category) else { return }
            candidates.append(
                SupplementalOCRCandidate(
                    span: match.span,
                    rects: [pixelRect(fromNormalized: match.rect)]
                )
            )
        }

        func looksLikeHonorificLine(_ text: String) -> Bool {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.compare("Herr", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                cleaned.compare("Frau", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        func appendLabeledAddressBlock(startingAt index: Int, includeLabelAsAddress: Bool = true) {
            guard page.lines.indices.contains(index) else { return }
            if includeLabelAsAddress {
                appendCandidate(lineIndex: index, category: "private_address")
            }

            let searchEnd = min(page.lines.count, index + 8)
            var blockIndices: [Int] = []
            var previousComparable = ""
            for cursor in (index + 1)..<searchEnd {
                let cleaned = page.lines[cursor].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                let comparable = cleaned
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .filter { $0.isLetter || $0.isNumber }
                if comparable == previousComparable, !comparable.isEmpty { continue }
                blockIndices.append(cursor)
                previousComparable = comparable
                if looksLikePostalCityLine(cleaned) { break }
            }

            guard !blockIndices.isEmpty else { return }

            var dataStart = 0
            if let firstIndex = blockIndices.first, looksLikeHonorificLine(page.lines[firstIndex].text) {
                appendCandidate(lineIndex: firstIndex, category: "private_person")
                dataStart = 1
            }

            for relativeIndex in dataStart..<blockIndices.count {
                let actualIndex = blockIndices[relativeIndex]
                let cleaned = page.lines[actualIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if relativeIndex == dataStart {
                    appendCandidate(lineIndex: actualIndex, category: "private_person")
                    continue
                }
                if looksLikeGermanStreetLine(cleaned) || looksLikePostalCityLine(cleaned) {
                    appendCandidate(lineIndex: actualIndex, category: "private_address")
                }
            }
        }

        func appendRecipientBlock(nameIndex: Int, sourceLabel: String) {
            guard let recipientBlock = resolveWindowRecipientBlock(in: page, nameIndex: nameIndex) else { return }

            let cleanedName = page.lines[nameIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            diagnostics.append(
                "Supplemental OCR hit: \(sourceLabel) at line \(nameIndex) -> '\(cleanedName)' | street='\(recipientBlock.street.trimmingCharacters(in: .whitespacesAndNewlines))' | city='\(recipientBlock.postalCity.trimmingCharacters(in: .whitespacesAndNewlines))'"
            )

            appendCandidate(lineIndex: nameIndex, category: "private_person")

            let streetRange = nameIndex + 1 ... recipientBlock.postalCityIndex
            let streetIndices = streetRange.filter { lineIndex in
                guard lineIndex < recipientBlock.postalCityIndex else { return false }
                let text = page.lines[lineIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                return looksLikeGermanStreetLine(text)
            }

            if streetIndices.isEmpty {
                appendCandidate(lineIndex: recipientBlock.streetIndex, category: "private_address")
            } else {
                for streetIndex in streetIndices {
                    appendCandidate(lineIndex: streetIndex, category: "private_address")
                }
            }

            appendCandidate(lineIndex: recipientBlock.postalCityIndex, category: "private_address")
        }

        func appendLabeledFormAddressBlock(startingAt index: Int) {
            let fieldOrder = ["vorname", "name", "strasse", "hausnr", "plz", "ort"]
            var labelLineIndices: [Int] = []
            var labelKeys: [String] = []
            var cursor = index

            while cursor < page.lines.count,
                  let key = standaloneFieldLabelKey(in: page.lines[cursor].text) {
                labelLineIndices.append(cursor)
                labelKeys.append(key)
                cursor += 1
            }

            guard !labelKeys.isEmpty else { return }

            let labelSummary = labelLineIndices.map { page.lines[$0].text }.joined(separator: " | ")
            diagnostics.append("Supplemental OCR hit: labeled form block at line \(index) -> '\(labelSummary)'")

            let orderedKeys = fieldOrder.filter { labelKeys.contains($0) }
            guard !orderedKeys.isEmpty else { return }

            var valueIndices: [Int] = []
            var scan = cursor
            while scan < page.lines.count, valueIndices.count < orderedKeys.count {
                let cleanedLine = page.lines[scan].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanedLine.isEmpty {
                    scan += 1
                    continue
                }
                if standaloneFieldLabelKey(in: cleanedLine) != nil {
                    break
                }
                valueIndices.append(scan)
                scan += 1
            }

            for (pairIndex, key) in orderedKeys.enumerated() {
                guard valueIndices.indices.contains(pairIndex) else { continue }
                let valueIndex = valueIndices[pairIndex]
                let valueText = page.lines[valueIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !valueText.isEmpty else { continue }

                switch key {
                case "vorname", "name":
                    appendCandidate(lineIndex: valueIndex, category: "private_person")
                case "strasse", "hausnr", "plz", "ort":
                    appendCandidate(lineIndex: valueIndex, category: "private_address")
                default:
                    break
                }
            }
        }

        diagnostics.append("Supplemental OCR candidates: start")
        for (index, line) in page.lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if cleaned.localizedCaseInsensitiveContains("Lieferadresse:") ||
                cleaned.localizedCaseInsensitiveContains("Lieferanschrift:") {
                diagnostics.append("Supplemental OCR hit: delivery-address block at line \(index) -> '\(cleaned)'")
                appendLabeledAddressBlock(startingAt: index)
                continue
            }

            if looksLikeLabeledFormBlockStart(cleaned),
               index == 0 || standaloneFieldLabelKey(in: page.lines[index - 1].text) == nil {
                appendLabeledFormAddressBlock(startingAt: index)
                continue
            }

            if let salutationName = salutationPersonName(in: cleaned) {
                diagnostics.append("Supplemental OCR hit: salutation at line \(index) -> '\(salutationName)'")
                appendCandidate(lineIndex: index, matchedText: salutationName, category: "private_person")
                continue
            }

            let looksLikeRecipientName = looksLikeWindowRecipientNameLine(cleaned)
            guard looksLikeRecipientName else { continue }

            let hasHeaderContext = hasNearbyOrganizationHeader(in: page, before: index)
            guard hasHeaderContext else { continue }
            appendRecipientBlock(nameIndex: index, sourceLabel: "window recipient block")
        }

        let rawPatternSpans = PatternMatcher.detectWithDiagnostics(modelInput).spans
        for span in rawPatternSpans {
            guard span.category == "custom_identifier",
                  span.confidence >= 0.95,
                  strongCustomIdentifierText(span.text),
                  let lineIndex = page.lineIndex(containing: span.start)
            else { continue }

            guard lineIndex < 12,
                  hasNearbyOrganizationHeader(in: page, before: lineIndex)
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

        var unique: [String: SupplementalOCRCandidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            let span = candidate.span
            let key = "\(span.category)::\(span.start)::\(span.end)::\(span.text)"
            if unique[key] == nil {
                order.append(key)
                unique[key] = candidate
            }
        }
        let deduplicated = order.compactMap { unique[$0] }
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

    private func salutationPersonName(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let patterns = [
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Frau|Herr)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized)
            else { continue }
            return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
        }
        return nil
    }

    private func looksLikeLabeledFormBlockStart(_ text: String) -> Bool {
        guard let key = standaloneFieldLabelKey(in: text) else { return false }
        return key == "vorname" || key == "name"
    }

    private func standaloneFieldLabelKey(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let mappings: [(label: String, key: String)] = [
            ("Vorname", "vorname"),
            ("Name", "name"),
            ("Nachname", "name"),
            ("Straße", "strasse"),
            ("Strasse", "strasse"),
            ("Strae", "strasse"),
            ("Street", "strasse"),
            ("Hausnr.", "hausnr"),
            ("Hausnr", "hausnr"),
            ("Hausnummer", "hausnr"),
            ("PLZ", "plz"),
            ("Postleitzahl", "plz"),
            ("Ort", "ort"),
            ("Stadt", "ort")
        ]
        for mapping in mappings {
            let pattern = #"(?i)^\#(NSRegularExpression.escapedPattern(for: mapping.label))\s*:\s*$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if regex.firstMatch(in: normalized, options: [], range: nsRange) != nil {
                return mapping.key
            }
        }
        return nil
    }

    private func strongCustomIdentifierText(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let tokenCount = cleaned.split(separator: " ").count
        return tokenCount >= 2
    }

    private func looksLikeWindowRecipientNameLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikeOrganizationHeaderLine(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func hasNearbyOrganizationHeader(in page: OCRPage, before index: Int) -> Bool {
        guard index > 0 else { return false }
        let start = max(0, index - 3)
        for previousIndex in start..<index {
            if looksLikeOrganizationHeaderLine(page.lines[previousIndex].text) {
                return true
            }
        }
        return false
    }

    private func resolveWindowRecipientBlock(in page: OCRPage, nameIndex: Int) -> (streetIndex: Int, street: String, postalCityIndex: Int, postalCity: String)? {
        let searchEnd = min(page.lines.count, nameIndex + 5)
        guard nameIndex + 1 < searchEnd else { return nil }

        var streetCandidates: [(index: Int, text: String)] = []
        for lineIndex in (nameIndex + 1)..<searchEnd {
            let text = page.lines[lineIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if looksLikeGermanStreetLine(text) {
                streetCandidates.append((lineIndex, text))
            }
        }

        guard !streetCandidates.isEmpty else { return nil }

        for streetCandidate in streetCandidates {
            let citySearchEnd = min(page.lines.count, streetCandidate.index + 4)
            guard streetCandidate.index + 1 < citySearchEnd else { continue }

            for cityIndex in (streetCandidate.index + 1)..<citySearchEnd {
                let text = page.lines[cityIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if looksLikePostalCityLine(text) {
                    return (streetCandidate.index, streetCandidate.text, cityIndex, text)
                }
            }
        }

        return nil
    }

    private func looksLikeGermanStreetLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikePostalCityLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func restoreMissingSupplementalCandidates(_ candidates: [SupplementalOCRCandidate]) {
        for candidate in candidates {
            let alreadyVisible = candidate.rects.contains { rect in
                isRectMostlyVisible(rect)
            }
            guard !alreadyVisible else { continue }

            let finding = ReviewFinding(
                category: candidate.span.category,
                snippet: candidate.span.text,
                source: candidate.span.source,
                confidence: candidate.span.confidence,
                pageIndex: nil
            )
            reviewFindings.append(finding)
            for rect in candidate.rects {
                addPreview(rect: rect, findingID: finding.id)
            }
        }
    }

    private func restoreMissingWindowRecipientPrelude(in page: OCRPage) {
        let searchLimit = min(page.lines.count, 12)
        guard searchLimit > 0 else { return }

        for cityIndex in 0..<searchLimit {
            let cityText = page.lines[cityIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikePostalCityLine(cityText),
                  let cityRect = page.normalizedLineBox(at: cityIndex).map(pixelRect(fromNormalized:)),
                  isRectMostlyVisible(cityRect)
            else { continue }

            let nameSearchStart = max(0, cityIndex - 4)
            let possibleNameIndices = Array(nameSearchStart..<cityIndex).filter { index in
                let text = page.lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
                return looksLikeWindowRecipientNameLine(text) && hasNearbyOrganizationHeader(in: page, before: index)
            }

            guard let nameIndex = possibleNameIndices.last else { continue }

            let streetIndices = Array((nameIndex + 1)..<cityIndex).filter { index in
                let text = page.lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
                return looksLikeGermanStreetLine(text)
            }

            guard !streetIndices.isEmpty else { continue }

            if let nameRect = page.normalizedLineBox(at: nameIndex).map(pixelRect(fromNormalized:)),
               !isRectMostlyVisible(nameRect),
               let nameSpan = page.lineSpan(at: nameIndex, category: "private_person") {
                appendRecoveredPreview(span: nameSpan, rect: nameRect)
            }

            for streetIndex in streetIndices {
                guard let streetRect = page.normalizedLineBox(at: streetIndex).map(pixelRect(fromNormalized:)),
                      !isRectMostlyVisible(streetRect),
                      let streetSpan = page.lineSpan(at: streetIndex, category: "private_address")
                else { continue }
                appendRecoveredPreview(span: streetSpan, rect: streetRect)
            }
        }
    }

    private func appendRecoveredPreview(span: DetectedSpan, rect: CGRect) {
        let finding = ReviewFinding(
            category: span.category,
            snippet: span.text,
            source: span.source,
            confidence: span.confidence,
            pageIndex: nil
        )
        reviewFindings.append(finding)
        addPreview(rect: rect, findingID: finding.id)
    }

    private func isRectMostlyVisible(_ rect: CGRect) -> Bool {
        previewEntries.contains { existing in
            let overlapRect = existing.rect.intersection(rect)
            guard !overlapRect.isNull else { return false }

            let candidateArea = max(rect.width * rect.height, 1)
            let overlapArea = overlapRect.width * overlapRect.height
            return overlapArea / candidateArea >= 0.6
        }
    }

    private func makePreviewDiagnostics(in page: OCRPage) -> [String] {
        var lines: [String] = []
        lines.append("Preview candidates: \(reviewFindings.count)")
        lines.append("Preview rects: \(previewEntries.count)")

        if reviewFindings.isEmpty {
            lines.append("Preview detail: <none>")
            return lines
        }

        for finding in reviewFindings {
            let rects = previewEntries.filter { $0.findingID == finding.id }.map(\.rect)
            let rectSummary = rects.enumerated().map { index, rect in
                "\(index): x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))"
            }.joined(separator: " | ")

            let matchedLineIndices = page.lines.enumerated().compactMap { index, line -> Int? in
                guard let normalizedRect = page.normalizedLineBox(at: index) else { return nil }
                let lineRect = pixelRect(fromNormalized: normalizedRect)
                return rects.contains(where: { rect in
                    let overlap = rect.intersection(lineRect)
                    guard !overlap.isNull else { return false }
                    let lineArea = max(lineRect.width * lineRect.height, 1)
                    return (overlap.width * overlap.height) / lineArea >= 0.4
                }) ? index : nil
            }

            let lineSummary = matchedLineIndices.map { index in
                "\(index): \(page.lines[index].text)"
            }.joined(separator: " | ")

            lines.append("[\(finding.category)] \(finding.snippet)")
            lines.append("  Source: \(finding.source.label) · \(Int(finding.confidence * 100))%")
            lines.append("  Rects: \(rectSummary.isEmpty ? "<none>" : rectSummary)")
            lines.append("  OCR lines: \(lineSummary.isEmpty ? "<none>" : lineSummary)")
        }

        return lines
    }

    func clearRedactions() {
        cancelDetection()
        redactionEntries.removeAll()
        previewEntries.removeAll()
        clearReviewState()
        if image != nil { phase = .loaded }
    }

    func addRedaction(rect: CGRect, findingID: UUID? = nil, rectIsPreNormalized: Bool = false) {
        let finalRect = rectIsPreNormalized ? rect : harmonizedDisplayRect(for: rect)
        redactionEntries.append(RedactionEntry(rect: finalRect, findingID: findingID))
        switch phase {
        case .loaded, .redacted:
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count)
        default:
            break
        }
    }

    private func addPreview(rect: CGRect, findingID: UUID) {
        previewEntries.append(RedactionEntry(rect: harmonizedDisplayRect(for: rect), findingID: findingID))
        if case .loaded = phase {
            phase = .redacted(spanCount: 0, rectCount: previewRects.count)
        }
    }

    func removeRedaction(at index: Int) {
        guard redactionEntries.indices.contains(index) else { return }
        let removed = redactionEntries.remove(at: index)
        if let findingID = removed.findingID {
            syncFindingStateAfterRedactionRemoval(findingID: findingID)
        }
        if redactionRects.isEmpty, image != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count)
        }
    }

    func acceptFinding(_ id: UUID) {
        promotePreviewToRedaction(for: id)
        dismissedPreviewEntries.removeAll { $0.findingID == id }
        updateFinding(id) { $0.status = .accepted }
        focusedFindingID = id
    }

    func acceptAllFindings() {
        let pendingIDs = reviewFindings
            .filter { $0.status == .pending }
            .map(\.id)
        for id in pendingIDs {
            acceptFinding(id)
        }
    }

    func rejectFinding(_ id: UUID) {
        let matches = previewEntries.filter { $0.findingID == id }
        previewEntries.removeAll { $0.findingID == id }
        dismissedPreviewEntries.append(contentsOf: matches)
        updateFinding(id) { $0.status = .rejected }
        if focusedFindingID == id { focusedFindingID = nil }
        if redactionRects.isEmpty && previewRects.isEmpty, image != nil {
            phase = .loaded
        } else if case .redacted = phase {
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        }
    }

    func reopenFinding(_ id: UUID) {
        guard let finding = reviewFindings.first(where: { $0.id == id }) else { return }

        switch finding.status {
        case .pending:
            focusedFindingID = id
        case .accepted:
            let matches = redactionEntries.filter { $0.findingID == id }
            guard !matches.isEmpty else { return }
            redactionEntries.removeAll { $0.findingID == id }
            previewEntries.append(contentsOf: matches)
            updateFinding(id) { $0.status = .pending }
            focusedFindingID = id
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        case .rejected:
            let matches = dismissedPreviewEntries.filter { $0.findingID == id }
            guard !matches.isEmpty else { return }
            dismissedPreviewEntries.removeAll { $0.findingID == id }
            previewEntries.append(contentsOf: matches)
            updateFinding(id) { $0.status = .pending }
            focusedFindingID = id
            phase = .redacted(spanCount: 0, rectCount: redactionRects.count + previewRects.count)
        }
    }

    func selectFinding(_ id: UUID) {
        focusedFindingID = id
    }

    func findingID(at point: CGPoint) -> UUID? {
        let match = (redactionEntries + previewEntries)
            .filter { $0.rect.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                if lhsArea == rhsArea {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhsArea < rhsArea
            }
        return match?.findingID
    }

    // MARK: - Helpers

    private func pixelRect(fromNormalized norm: CGRect) -> CGRect {
        let w = CGFloat(image?.width ?? 0)
        let h = CGFloat(image?.height ?? 0)
        let x = norm.minX * w
        let y = (1 - norm.maxY) * h
        return CGRect(x: x, y: y, width: norm.width * w, height: norm.height * h)
    }

    private func harmonizedDisplayRect(for rect: CGRect) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: pixelSize)
        let workingRect = rect.standardized
        guard redactionStyle == .blackRectangle else {
            return workingRect.insetBy(dx: -1, dy: -1).intersection(imageBounds)
        }

        let targetHeight = max(12, round(workingRect.height + 4))
        let adjusted = CGRect(
            x: workingRect.minX - 1,
            y: workingRect.midY - (targetHeight / 2),
            width: workingRect.width + 2,
            height: targetHeight
        )
        return adjusted.intersection(imageBounds)
    }

    private func writeRedacted(to url: URL, uti: UTType, options: ExportOptions) -> ExportResult? {
        guard let cg = image else { return nil }
        guard let baked = bakeRedactions(into: cg) else { return nil }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, baked, imageProperties(for: uti, options: options))
        guard CGImageDestinationFinalize(dest) else { return nil }

        let report = ExportValidationReport(
            format: .image,
            redactionCount: redactionRects.count,
            redactedPageCount: nil,
            totalPageCount: nil,
            removedMetadata: options.removeMetadata,
            annotationsRemoved: true,
            bakedIntoPixels: !redactionRects.isEmpty
        )
        return ExportResult(url: url, report: report)
    }

    private func imageProperties(for uti: UTType, options: ExportOptions) -> CFDictionary? {
        var properties = options.removeMetadata ? [:] : sourceImageProperties ?? [:]
        properties[kCGImagePropertyOrientation] = 1

        if options.removeMetadata {
            if uti.conforms(to: .png) {
                properties[kCGImagePropertyPNGDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .jpeg) {
                properties[kCGImagePropertyJFIFDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .tiff) {
                properties[kCGImagePropertyTIFFDictionary] = [:] as CFDictionary
            }
        }

        return properties as CFDictionary
    }

    private func bakeRedactions(into image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let flippedRects = redactionRects.map { r in
            CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height)
                .insetBy(dx: -2, dy: -2)
        }

        switch redactionStyle {
        case .blackRectangle:
            ctx.setFillColor(NSColor.black.cgColor)
            for r in flippedRects { ctx.fill(r) }

        case .blur:
            guard let snapshot = ctx.makeImage(),
                  let blurred = gaussianBlurred(snapshot) else { return nil }
            for r in flippedRects {
                ctx.saveGState()
                ctx.clip(to: r)
                ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
                ctx.restoreGState()
            }
        }

        return ctx.makeImage()
    }

    private func gaussianBlurred(_ sharp: CGImage) -> CGImage? {
        let sharpCI = CIImage(cgImage: sharp)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = sharpCI
        blur.radius = Float(min(sharp.width, sharp.height)) * 0.02
        guard let blurredCI = blur.outputImage?.cropped(to: sharpCI.extent) else { return nil }
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        return ciContext.createCGImage(blurredCI, from: blurredCI.extent)
    }

    private func suggestedSaveName(uti: UTType) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "bild"
        let ext = uti.preferredFilenameExtension ?? "png"
        return "\(base)-geschwaerzt.\(ext)"
    }

    func findingRects(for findingID: UUID) -> [CGRect] {
        (previewEntries + redactionEntries)
            .filter { $0.findingID == findingID }
            .map(\.rect)
    }

    func findingColor(for findingID: UUID?) -> NSColor {
        guard let findingID,
              let finding = reviewFindings.first(where: { $0.id == findingID })
        else {
            return .systemOrange
        }

        switch finding.category.lowercased() {
        case "private_email", "kontakt":
            return .systemGreen
        case "private_address", "adressblock", "adresse":
            return .systemRed
        case "account_number":
            return NSColor.systemYellow.blended(withFraction: 0.28, of: .systemOrange) ?? .systemYellow
        case "private_phone":
            return .systemTeal
        case "private_person":
            return .systemBlue
        case "private_date":
            return .systemPurple
        default:
            return .systemOrange
        }
    }

    private func clearReviewState() {
        reviewFindings.removeAll()
        focusedFindingID = nil
        debugEntries.removeAll()
        dismissedPreviewEntries.removeAll()
    }

    private func promotePreviewToRedaction(for findingID: UUID) {
        let matches = previewEntries.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }
        previewEntries.removeAll { $0.findingID == findingID }
        for entry in matches {
            addRedaction(rect: entry.rect, findingID: findingID, rectIsPreNormalized: true)
        }
    }

    private func syncFindingStateAfterRedactionRemoval(findingID: UUID) {
        guard !redactionEntries.contains(where: { $0.findingID == findingID }) else { return }
        updateFinding(findingID) {
            if $0.status == .pending {
                $0.status = .rejected
            }
        }
    }

    private func updateFinding(_ id: UUID, mutate: (inout ReviewFinding) -> Void) {
        guard let index = reviewFindings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&reviewFindings[index])
    }
}

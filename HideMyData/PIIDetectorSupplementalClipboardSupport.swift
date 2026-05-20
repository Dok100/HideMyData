import Foundation

enum PIIDetectorSupplementalClipboardSupport {
    private struct ClipboardTextLine {
        let text: String
        let range: NSRange
    }

    nonisolated static func classifyDocumentText(_ text: String) -> DetectionDocumentClass {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var scores: [DetectionDocumentClass: Int] = [
            .invoice: 0,
            .taxNotice: 0,
            .contactBankPage: 0,
            .standardizedForm: 0
        ]

        let invoiceMarkers = [
            "rechnung", "rechnungsanschrift", "lieferanschrift", "lieferadresse",
            "bestellt durch", "kundennummer", "vertragsnummer", "zahlernummer",
            "zaehlernummer", "lieferstelle", "nutzungsadresse", "rechnungs-nr",
            "rechnungsdatum", "lieferdatum", "gesamtbetrag brutto",
            "zahlungsbedingungen", "e-rechnung", "erechnung", "zugferd", "xrechnung",
            "leitweg-id", "rechnungsempfanger", "rechnungsempfänger", "lieferanten-nr",
            "leistungszeitraum", "falliger rechnungsbetrag", "fälliger rechnungsbetrag",
            "swift-code"
        ]
        let taxMarkers = [
            "finanzamt", "steuerbescheid", "einkommensteuer", "kirchensteuer",
            "solidaritatszuschlag", "steuernummer", "idnr", "bescheid"
        ]
        let contactBankMarkers = [
            "iban", "bic", "kontoinhaber", "kontonummer", "girokonto",
            "girokontonummer", "buchungskonto", "bankverbindung", "ansprechpartner",
            "kontakt", "telefon", "mobil"
        ]

        for marker in invoiceMarkers where normalized.contains(marker) {
            scores[.invoice, default: 0] += 2
        }
        for marker in taxMarkers where normalized.contains(marker) {
            scores[.taxNotice, default: 0] += 2
        }
        for marker in contactBankMarkers where normalized.contains(marker) {
            scores[.contactBankPage, default: 0] += 2
        }

        if normalized.contains("vorname"),
           normalized.contains("name"),
           normalized.contains("plz"),
           normalized.contains("ort") {
            scores[.standardizedForm, default: 0] += 4
        }

        if looksLikeStandaloneFieldSequence(in: text) {
            scores[.standardizedForm, default: 0] += 5
        }

        let best = scores.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue > rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }

        guard let best, best.value > 0 else { return .general }
        return best.key
    }

    nonisolated static func supplementalClipboardSpans(in text: String) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []
        let lines = clipboardTextLines(in: text)
        let documentClass = classifyDocumentText(text)
        let addressLabels = addressBlockLabels(for: documentClass)
        let personFieldLabels = personFieldLabels(for: documentClass)
        let streetFieldLabels = streetFieldLabels(for: documentClass)
        let houseNumberFieldLabels = houseNumberFieldLabels(for: documentClass)
        let postalCodeFieldLabels = postalCodeFieldLabels(for: documentClass)
        let cityFieldLabels = cityFieldLabels(for: documentClass)

        func appendSpan(for line: ClipboardTextLine, category: String) {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            spans.append(
                DetectedSpan(
                    category: category,
                    text: cleaned,
                    start: line.range.location,
                    end: line.range.location + line.range.length,
                    confidence: 0.99,
                    source: .pattern
                )
            )
        }

        func appendStandaloneFieldValueBlock(startingAt index: Int) {
            let fieldOrder = ["vorname", "name", "strasse", "hausnr", "plz", "ort"]
            var labelKeys: [String] = []
            var cursor = index

            while cursor < lines.count,
                  let key = standaloneFieldLabelKey(in: lines[cursor].text) {
                labelKeys.append(key)
                cursor += 1
            }

            let orderedKeys = fieldOrder.filter { labelKeys.contains($0) }
            guard orderedKeys.count >= 3 else { return }

            var valueLines: [ClipboardTextLine] = []
            var scan = cursor
            while scan < lines.count, valueLines.count < orderedKeys.count {
                let cleaned = lines[scan].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    scan += 1
                    continue
                }
                if standaloneFieldLabelKey(in: cleaned) != nil {
                    break
                }
                valueLines.append(lines[scan])
                scan += 1
            }

            for (pairIndex, key) in orderedKeys.enumerated() {
                guard valueLines.indices.contains(pairIndex) else { continue }
                let valueLine = valueLines[pairIndex]
                switch key {
                case "vorname", "name":
                    appendSpan(for: valueLine, category: "private_person")
                case "strasse", "hausnr", "plz", "ort":
                    appendSpan(for: valueLine, category: "private_address")
                default:
                    break
                }
            }
        }

        if documentClass == .standardizedForm {
            for (index, line) in lines.enumerated() {
                let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty,
                      looksLikeLabeledFormBlockStart(cleaned),
                      (index == 0 || standaloneFieldLabelKey(in: lines[index - 1].text) == nil)
                else { continue }
                appendStandaloneFieldValueBlock(startingAt: index)
            }
        }

        for (index, line) in lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard addressLabels.contains(where: { cleaned.localizedCaseInsensitiveContains($0) }) else { continue }

            var previousComparable = ""
            let searchEnd = min(lines.count, index + 8)
            for nextIndex in (index + 1)..<searchEnd {
                let nextLine = lines[nextIndex]
                let nextCleaned = nextLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nextCleaned.isEmpty else { continue }

                let comparable = PIIDetectorSpanSanitizationSupport.normalizedComparableText(nextCleaned)
                if !comparable.isEmpty && comparable == previousComparable { continue }
                previousComparable = comparable

                if nextCleaned.compare("Deutschland", options: .caseInsensitive) == .orderedSame {
                    break
                }

                if looksLikeHonorificOnlyLine(nextCleaned) || PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(nextCleaned) {
                    appendSpan(for: nextLine, category: "private_person")
                    continue
                }

                if PIIDetectorSpanSanitizationSupport.looksLikeGermanStreetAddress(nextCleaned) ||
                    PIIDetectorSpanSanitizationSupport.looksLikeStreetNameOnlyLine(nextCleaned) ||
                    PIIDetectorSpanSanitizationSupport.looksLikeHouseNumberOnlyLine(nextCleaned) ||
                    PIIDetectorSpanSanitizationSupport.looksLikePostalCity(nextCleaned) {
                    appendSpan(for: nextLine, category: "private_address")
                    if PIIDetectorSpanSanitizationSupport.looksLikePostalCity(nextCleaned) { break }
                }
            }
        }

        for (index, line) in lines.enumerated() {
            let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let compactLabel = cleaned.replacingOccurrences(of: ":", with: "")

            guard !compactLabel.isEmpty else { continue }
            guard let valueLine = nextNonEmptyClipboardLine(after: index, in: lines) else { continue }

            let value = valueLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            if personFieldLabels.contains(where: { compactLabel.localizedCaseInsensitiveContains($0) }) {
                if looksLikeHonorificOnlyLine(value) || PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(value) {
                    appendSpan(for: valueLine, category: "private_person")
                }
                continue
            }

            if streetFieldLabels.contains(where: { compactLabel.localizedCaseInsensitiveContains($0) }) {
                if PIIDetectorSpanSanitizationSupport.looksLikeGermanStreetAddress(value) ||
                    PIIDetectorSpanSanitizationSupport.looksLikeStreetNameOnlyLine(value) {
                    appendSpan(for: valueLine, category: "private_address")
                }
                continue
            }

            if houseNumberFieldLabels.contains(where: { compactLabel.localizedCaseInsensitiveContains($0) }) {
                if PIIDetectorSpanSanitizationSupport.looksLikeHouseNumberOnlyLine(value) {
                    appendSpan(for: valueLine, category: "private_address")
                }
                continue
            }

            if postalCodeFieldLabels.contains(where: { compactLabel.localizedCaseInsensitiveContains($0) }) {
                if PIIDetectorSpanSanitizationSupport.looksLikePostalCodeOnlyLine(value) {
                    appendSpan(for: valueLine, category: "private_address")
                }
                continue
            }

            if cityFieldLabels.contains(where: { compactLabel.localizedCaseInsensitiveContains($0) }) {
                if PIIDetectorSpanSanitizationSupport.looksLikeCityNameOnlyLine(value) {
                    appendSpan(for: valueLine, category: "private_address")
                }
            }
        }

        spans.append(contentsOf: supplementalInlinePersonSpans(in: text))

        return spans
    }

    nonisolated static func supplementalInlinePersonSpans(in text: String) -> [DetectedSpan] {
        let inlinePatterns = [
            #"\b(?:name|bestellt\s+durch|besteller(?:in)?|kunde|kundin|kontoinhaber|ansprechpartner)\s*:\s*((?:Herr|Herrn|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}|[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+,\s*[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?|[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2})\b"#,
            #"\b((?:Herr|Herrn|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
            #"\b([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+,\s*[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?)\b"#
        ]

        var spans: [DetectedSpan] = []
        var seenRanges: Set<String> = []

        for pattern in inlinePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

            for match in regex.matches(in: text, options: [], range: nsRange) {
                guard match.numberOfRanges > 1 else { continue }
                let range = match.range(at: 1)
                guard range.location != NSNotFound,
                      let swiftRange = Range(range, in: text) else { continue }

                let snippet = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
                guard !snippet.isEmpty,
                      !PIIDetectorSpanSanitizationSupport.looksLikeOrganizationSnippet(snippet),
                      !PIIDetectorSpanSanitizationSupport.personSpanContainsAddressOrContactTail(snippet)
                else { continue }

                let key = "\(range.location):\(range.length):\(PIIDetectorSpanSanitizationSupport.normalizedComparableText(snippet))"
                guard seenRanges.insert(key).inserted else { continue }

                spans.append(
                    DetectedSpan(
                        category: "private_person",
                        text: snippet,
                        start: range.location,
                        end: range.location + range.length,
                        confidence: 0.93,
                        source: .pattern
                    )
                )
            }
        }

        return spans
    }

    nonisolated static func looksLikeStandaloneFieldSequence(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var consecutiveCount = 0

        for line in lines {
            if standaloneFieldLabelKey(in: line) != nil {
                consecutiveCount += 1
                if consecutiveCount >= 3 {
                    return true
                }
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                consecutiveCount = 0
            }
        }

        return false
    }

    nonisolated private static func addressBlockLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .invoice:
            return [
                "Rechnungsanschrift", "Lieferanschrift", "Lieferadresse", "Rechnungsadresse",
                "Postanschrift", "Korrespondenzanschrift", "Lieferstelle", "Nutzungsadresse",
                "Objektanschrift"
            ]
        case .taxNotice:
            return ["Postanschrift", "Korrespondenzanschrift", "Anschrift", "Steuerpflichtige Person"]
        case .contactBankPage:
            return ["Postanschrift", "Korrespondenzanschrift", "Objektanschrift", "Nutzungsadresse"]
        case .standardizedForm:
            return ["Postanschrift", "Korrespondenzanschrift", "Anschrift"]
        case .general:
            return ["Rechnungsanschrift", "Lieferanschrift", "Postanschrift", "Korrespondenzanschrift"]
        }
    }

    nonisolated private static func personFieldLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .invoice:
            return ["Vorname", "Name", "Nachname", "Bestellt durch", "Kunde", "Kundin"]
        case .taxNotice:
            return ["Vorname", "Name", "Nachname", "Steuerpflichtige Person", "Steuerpflichtiger"]
        case .contactBankPage:
            return ["Vorname", "Name", "Nachname", "Kontoinhaber", "Versicherungsnehmer", "Darlehensnehmer", "Anschlussinhaber", "Ansprechpartner"]
        case .standardizedForm:
            return ["Vorname", "Name", "Nachname", "Kunde", "Kundin", "Kontoinhaber"]
        case .general:
            return ["Vorname", "Name", "Nachname", "Bestellt durch", "Kunde", "Kontoinhaber"]
        }
    }

    nonisolated private static func streetFieldLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .general, .invoice, .taxNotice, .contactBankPage, .standardizedForm:
            return ["Straße", "Strasse"]
        }
    }

    nonisolated private static func houseNumberFieldLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .general, .invoice, .taxNotice, .contactBankPage, .standardizedForm:
            return ["Hausnr", "Hausnummer"]
        }
    }

    nonisolated private static func postalCodeFieldLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .general, .invoice, .taxNotice, .contactBankPage, .standardizedForm:
            return ["PLZ", "Postleitzahl"]
        }
    }

    nonisolated private static func cityFieldLabels(for documentClass: DetectionDocumentClass) -> [String] {
        switch documentClass {
        case .general, .invoice, .taxNotice, .contactBankPage, .standardizedForm:
            return ["Ort", "Stadt"]
        }
    }

    nonisolated private static func clipboardTextLines(in text: String) -> [ClipboardTextLine] {
        let nsText = text as NSString
        var lines: [ClipboardTextLine] = []
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            lines.append(ClipboardTextLine(text: nsText.substring(with: substringRange), range: substringRange))
        }
        return lines
    }

    nonisolated private static func looksLikeHonorificOnlyLine(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.range(of: #"(?i)^(?:frau|herr)$"#, options: .regularExpression) != nil
    }

    nonisolated private static func nextNonEmptyClipboardLine(after index: Int, in lines: [ClipboardTextLine]) -> ClipboardTextLine? {
        guard index < lines.count - 1 else { return nil }
        for nextIndex in (index + 1)..<lines.count {
            let cleaned = lines[nextIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return lines[nextIndex]
            }
        }
        return nil
    }

    nonisolated private static func looksLikeLabeledFormBlockStart(_ text: String) -> Bool {
        guard let key = standaloneFieldLabelKey(in: text) else { return false }
        return key == "vorname" || key == "name"
    }

    nonisolated private static func standaloneFieldLabelKey(in text: String) -> String? {
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
}

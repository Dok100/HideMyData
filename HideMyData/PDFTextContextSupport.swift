import Foundation

enum PDFTextContextSupport {
    static func looksLikeRecipientMarkerLine(_ line: String) -> Bool {
        let cleaned = line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let explicitPrefixes = [
            "kundin:", "kunde:", "lieferadresse:", "schriftverkehr", "kontoinhaber:",
            "abweichender ansprechpartner:", "bestellt durch:", "besteller:", "bestellerin:", "name:",
            "eheleute", "herr", "frau",
            "versicherungsnehmer", "darlehensnehmer", "postanschrift",
            "korrespondenzanschrift", "objektanschrift", "rechnungsanschrift",
            "lieferstelle", "anschlussinhaber", "nutzungsadresse"
        ]
        return explicitPrefixes.contains(where: { cleaned.hasPrefix($0) })
    }

    static func contextualRedactionLabelLines(
        for span: DetectedSpan,
        in pageText: String
    ) -> [NativePDFPageTextLine] {
        let compactSpan = NativePDFContextAnalyzer.normalizedComparableText(span.text)
        guard !compactSpan.isEmpty,
              let spanRange = nsRange(start: span.start, end: span.end, in: pageText)
        else {
            return []
        }

        let lines = NativePDFContextAnalyzer.pageTextLines(in: pageText)
        var matches: [NativePDFPageTextLine] = []
        var seen = Set<String>()

        for (index, line) in lines.enumerated() {
            let cleanedLine = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedLine.isEmpty else { continue }

            let compactLine = NativePDFContextAnalyzer.normalizedComparableText(cleanedLine)
            let lineContainsSpan = compactLine.contains(compactSpan)
            let overlapsSpanRange = NSIntersectionRange(line.range, spanRange).length > 0
            guard lineContainsSpan || overlapsSpanRange else { continue }

            if isRedactionContextLabelLine(cleanedLine), seen.insert(cleanedLine).inserted {
                matches.append(line)
            }

            for offset in 1...3 {
                let previousIndex = index - offset
                guard previousIndex >= 0 else { break }
                let previousLine = lines[previousIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if previousLine.isEmpty { continue }
                if isRedactionContextLabelLine(previousLine), seen.insert(previousLine).inserted {
                    matches.append(lines[previousIndex])
                }
                break
            }
        }

        return matches
    }

    private static func isRedactionContextLabelLine(_ line: String) -> Bool {
        let normalizedLine = line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let markers = [
            "abweichender ansprechpartner",
            "lieferadresse",
            "versicherungsnehmer",
            "darlehensnehmer",
            "anschlussinhaber",
            "lieferstelle",
            "postanschrift",
            "korrespondenzanschrift",
            "objektanschrift",
            "nutzungsadresse",
            "rechnungsanschrift",
            "schriftverkehr",
            "fuer rueckfragen",
            "fur ruckfragen",
            "rueckfragen",
            "ruckfragen",
            "hier erreichen wir sie bei rueckfragen",
            "hier liefern wir ihren strom hin",
            "hierauf stellen wir ihre rechnung aus"
        ]
        return markers.contains { normalizedLine.contains($0) }
    }

    private static func nsRange(start: Int, end: Int, in text: String) -> NSRange? {
        guard start <= text.count, end <= text.count, start <= end else { return nil }
        let s = text.index(text.startIndex, offsetBy: start)
        let e = text.index(text.startIndex, offsetBy: end)
        let utf16Start = text.utf16.distance(from: text.utf16.startIndex, to: s.samePosition(in: text.utf16) ?? text.utf16.startIndex)
        let utf16End = text.utf16.distance(from: text.utf16.startIndex, to: e.samePosition(in: text.utf16) ?? text.utf16.startIndex)
        return NSRange(location: utf16Start, length: utf16End - utf16Start)
    }
}

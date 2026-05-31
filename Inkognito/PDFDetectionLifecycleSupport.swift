import Foundation

enum PDFPageTextSource {
    case nativeText(String)
    case ocr(OCRPage)

    var text: String {
        switch self {
        case .nativeText(let text):
            return text
        case .ocr(let page):
            return page.combinedText
        }
    }

    var debugLabel: String {
        switch self {
        case .nativeText:
            return "PDF-Text"
        case .ocr:
            return "Apple Vision OCR"
        }
    }

    var ocrPage: OCRPage? {
        switch self {
        case .nativeText:
            return nil
        case .ocr(let page):
            return page
        }
    }
}

struct PDFPageDetectionInput {
    let source: PDFPageTextSource
    let modelInput: String
    let offsetMap: [Int]
    let usedNativeText: Bool
    let usedOCRText: Bool
}

enum PDFDetectionLifecycleSupport {
    static func pageDetectionInput(
        pageText: String,
        ocrPage: OCRPage?
    ) -> PDFPageDetectionInput? {
        let trimmedPageText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldPreferOCR = trimmedPageText.isEmpty || nativeTextLikelyNeedsOCR(trimmedPageText)

        if shouldPreferOCR, let ocrPage, !ocrPage.combinedText.isEmpty {
            let normalized = OCRNormalizer.normalize(ocrPage.combinedText, mode: .ocr)
            return PDFPageDetectionInput(
                source: .ocr(ocrPage),
                modelInput: normalized.text,
                offsetMap: normalized.offsetMap,
                usedNativeText: false,
                usedOCRText: true
            )
        }

        guard !trimmedPageText.isEmpty else { return nil }
        let normalized = OCRNormalizer.normalize(pageText, mode: .native)
        return PDFPageDetectionInput(
            source: .nativeText(pageText),
            modelInput: normalized.text,
            offsetMap: normalized.offsetMap,
            usedNativeText: true,
            usedOCRText: false
        )
    }

    static func completionNotice(
        reviewFindingsEmpty: Bool,
        totalSpans: Int,
        usedNativeText: Bool,
        usedOCRText: Bool,
        pagesWithoutUsableText: Int
    ) -> DocumentDetectionNotice? {
        guard reviewFindingsEmpty, totalSpans == 0 else { return nil }

        if !usedNativeText && !usedOCRText {
            return DocumentDetectionNotice(
                title: "Kaum lesbarer Text im PDF",
                message: "Inkognito konnte in diesem PDF keinen ausreichend lesbaren Text finden. Häufig ist das bei gescannten Seiten, sehr schwachen Exporten oder rein bildbasierten PDFs der Fall."
            )
        }

        if usedOCRText && pagesWithoutUsableText > 0 {
            return DocumentDetectionNotice(
                title: "OCR nur teilweise brauchbar",
                message: "Ein Teil der Seiten lieferte kaum verwertbaren Text. Wenn etwas sichtbar fehlt, versuche bitte eine klarere Scan-Version oder prüfe die Seite manuell."
            )
        }

        return nil
    }

    private static func nativeTextLikelyNeedsOCR(_ text: String) -> Bool {
        let ocrLikeNormalized = OCRNormalizer.normalize(text, mode: .ocr).text
        let nativeNormalized = OCRNormalizer.normalize(text, mode: .native).text
        let rawCount = max(text.count, 1)
        let compactedCount = max(0, nativeNormalized.count - ocrLikeNormalized.count)
        let compactionRatio = Double(compactedCount) / Double(rawCount)

        let spacedRunCount = matches(
            for: #"(?u)(?:\b[\p{L}\p{N}]\s+){3,}[\p{L}\p{N}]\b"#,
            in: text
        )
        let suspiciousSymbolCount = text.filter { "^�".contains($0) }.count

        if spacedRunCount >= 3 { return true }
        if spacedRunCount >= 2, compactionRatio > 0.05 { return true }
        if compactionRatio > 0.12 { return true }
        if suspiciousSymbolCount >= 2, compactionRatio > 0.04 { return true }
        return false
    }

    private static func matches(for pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

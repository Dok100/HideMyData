import Foundation
import PDFKit

enum PDFExportLifecycleResult {
    case success(RedactionExportResult)
    case failure(String)
}

enum PDFExportLifecycleSupport {
    static func saveRedactedCopy(
        sourceDocument doc: PDFDocument,
        destinationURL url: URL,
        options: ExportOptions,
        redactionStyle: RedactionStyle,
        manualRedactionCount: Int,
        detectionNotice: DocumentDetectionNotice?,
        rectsForPage: (PDFPage) -> [CGRect],
        detachableAnnotationsForPage: (PDFPage) -> [PDFAnnotation]
    ) -> PDFExportLifecycleResult {
        let newDoc = PDFDocument()
        newDoc.documentAttributes = options.removeMetadata ? [:] : doc.documentAttributes
        var redactedPageCount = 0

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let pageRects = rectsForPage(page)

            if pageRects.isEmpty && !options.removeMetadata {
                if let copy = page.copy() as? PDFPage {
                    newDoc.insert(copy, at: newDoc.pageCount)
                }
                continue
            }

            let detached = detachableAnnotationsForPage(page)
            guard let baked = RedactionRendering.bakePDFPage(
                page,
                rects: pageRects,
                style: redactionStyle,
                detaching: detached
            ) else {
                return .failure("Das PDF konnte nicht exportiert werden, weil mindestens eine Seite nicht sauber neu aufgebaut werden konnte. Bitte versuche es erneut oder speichere an einen anderen Ort.")
            }
            newDoc.insert(baked, at: newDoc.pageCount)
            redactedPageCount += 1
        }

        guard newDoc.write(to: url) else {
            return .failure("Die geschwärzte PDF konnte nicht am gewählten Ort gespeichert werden. Bitte prüfe Schreibrechte, freien Speicherplatz oder wähle einen anderen Speicherort.")
        }

        let report = ExportValidationReport(
            format: .pdf,
            redactionCount: redactionCount(in: doc, rectsForPage: rectsForPage),
            manualRedactionCount: manualRedactionCount,
            redactedPageCount: redactedPageCount,
            totalPageCount: newDoc.pageCount,
            lowTextWarning: detectionNotice?.title.localizedCaseInsensitiveContains("lesbarer Text") == true
                || detectionNotice?.title.localizedCaseInsensitiveContains("OCR") == true,
            removedMetadata: options.removeMetadata,
            annotationsRemoved: documentLooksAnnotationFree(newDoc),
            bakedIntoPixels: redactedPageCount > 0
        )

        return .success(RedactionExportResult(url: url, report: report))
    }

    static func suggestedSaveName(for sourceURL: URL?) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "dokument"
        return "\(base)-geschwaerzt.pdf"
    }

    static func documentLooksAnnotationFree(_ document: PDFDocument) -> Bool {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if !page.annotations.isEmpty {
                return false
            }
        }
        return true
    }

    private static func redactionCount(
        in document: PDFDocument,
        rectsForPage: (PDFPage) -> [CGRect]
    ) -> Int {
        var count = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            count += rectsForPage(page).count
        }
        return count
    }
}

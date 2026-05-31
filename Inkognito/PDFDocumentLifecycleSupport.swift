import AppKit
import Foundation
import PDFKit
internal import UniformTypeIdentifiers

enum PDFDocumentLifecycleSupport {
    struct LoadedDocument {
        let document: PDFDocument
        let sourceURL: URL
        let pageCount: Int
    }

    enum LoadResult {
        case success(LoadedDocument)
        case failure(String)
    }

    static func presentOpenPanel(loadPDFFromURL: (URL) -> Bool) -> DocumentOpenResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard loadPDFFromURL(url) else {
            return .failed("Das PDF „\(url.lastPathComponent)“ konnte nicht geöffnet werden. Prüfe bitte, ob die Datei vollständig ist und wirklich ein lesbares PDF enthält.")
        }
        return .opened(url)
    }

    static func loadDocument(from url: URL) -> LoadResult {
        guard let document = PDFDocument(url: url) else {
            return .failure("PDF konnte nicht geöffnet werden: \(url.lastPathComponent)")
        }
        return .success(LoadedDocument(document: document, sourceURL: url, pageCount: document.pageCount))
    }

    static func loadDocument(data: Data, originalURL: URL) -> LoadResult {
        guard let document = PDFDocument(data: data) else {
            return .failure("PDF konnte nicht geöffnet werden: \(originalURL.lastPathComponent)")
        }
        return .success(LoadedDocument(document: document, sourceURL: originalURL, pageCount: document.pageCount))
    }

    static func makeSavePanel(sourceURL: URL?) -> (panel: NSSavePanel, accessory: ExportOptionsAccessoryView) {
        let panel = NSSavePanel()
        let accessory = ExportOptionsAccessoryView()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.title = "Geschützte Kopie speichern"
        panel.message = "Wähle Speicherort und Dateinamen für das geschützte PDF."
        panel.prompt = "Speichern"
        panel.nameFieldLabel = "Dateiname:"
        panel.showsTagField = false
        panel.nameFieldStringValue = PDFExportLifecycleSupport.suggestedSaveName(for: sourceURL)
        panel.accessoryView = accessory
        return (panel, accessory)
    }
}

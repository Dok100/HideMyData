import Foundation
import PDFKit

@MainActor
enum PDFAnnotationMutationSupport {
    @discardableResult
    static func addRedaction(
        rect: CGRect,
        on page: PDFPage,
        findingID: UUID?,
        rectIsPreNormalized: Bool,
        redactionStyle: RedactionStyle,
        blurredImage: CGImage?,
        redactionAnnotations: inout [PDFRedactor.RedactionEntry]
    ) -> PDFAnnotation {
        let bounds = rectIsPreNormalized
            ? rect
            : PDFAnnotationStyleSupport.normalizedDisplayRect(for: rect, on: page, redactionStyle: redactionStyle)
        let annotation = PDFAnnotationStyleSupport.makeRedactionAnnotation(
            bounds: bounds,
            style: redactionStyle,
            page: page,
            blurredImage: blurredImage
        )
        page.addAnnotation(annotation)
        redactionAnnotations.append(
            PDFRedactor.RedactionEntry(page: page, annotation: annotation, findingID: findingID)
        )
        return annotation
    }

    @discardableResult
    static func addPreview(
        rect: CGRect,
        on page: PDFPage,
        findingID: UUID,
        category: String?,
        rectIsPreNormalized: Bool,
        redactionStyle: RedactionStyle,
        previewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) -> PDFAnnotation {
        let bounds = rectIsPreNormalized
            ? rect
            : PDFAnnotationStyleSupport.normalizedDisplayRect(for: rect, on: page, redactionStyle: redactionStyle)
        let annotation = PDFAnnotationStyleSupport.makePreviewAnnotation(bounds: bounds, category: category)
        page.addAnnotation(annotation)
        previewAnnotations.append(
            PDFRedactor.RedactionEntry(page: page, annotation: annotation, findingID: findingID)
        )
        return annotation
    }

    static func rebuildRedactions(
        from snapshot: [PDFRedactor.RedactionEntry],
        redactionStyle: RedactionStyle,
        blurredImageProvider: (PDFPage) -> CGImage?,
        redactionAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        redactionAnnotations.removeAll()
        for entry in snapshot {
            let bounds = entry.annotation.bounds
            entry.page.removeAnnotation(entry.annotation)
            _ = addRedaction(
                rect: bounds,
                on: entry.page,
                findingID: entry.findingID,
                rectIsPreNormalized: true,
                redactionStyle: redactionStyle,
                blurredImage: redactionStyle == .blur ? blurredImageProvider(entry.page) : nil,
                redactionAnnotations: &redactionAnnotations
            )
        }
    }
}

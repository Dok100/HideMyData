import AppKit
import Foundation
import PDFKit

@MainActor
enum PDFPageRenderSupport {
    static func renderPageToCGImage(
        _ page: PDFPage,
        scale: CGFloat,
        detaching annotations: [PDFAnnotation]
    ) -> CGImage? {
        RedactionRendering.renderPDFPageSnapshot(page, scale: scale, detaching: annotations)
    }

    static func blurredImage(
        for page: PDFPage,
        using cache: NSCache<PDFPage, CGImage>,
        detaching annotations: [PDFAnnotation]
    ) -> CGImage? {
        if let cached = cache.object(forKey: page) { return cached }
        guard let sharpCG = renderPageToCGImage(page, scale: 2, detaching: annotations),
              let blurred = RedactionRendering.gaussianBlurred(sharpCG) else { return nil }
        cache.setObject(blurred, forKey: page)
        return blurred
    }
}

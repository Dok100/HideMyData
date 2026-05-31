import AppKit
import Foundation
import PDFKit

@MainActor
enum PDFAnnotationStyleSupport {
    static func normalizedDisplayRect(
        for rect: CGRect,
        on page: PDFPage,
        redactionStyle: RedactionStyle
    ) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let workingRect = rect.standardized
        guard redactionStyle == .blackRectangle else {
            return workingRect.insetBy(dx: -1, dy: -1).intersection(pageBounds)
        }

        let targetHeight = max(12, round(workingRect.height + 4))
        let centerY = workingRect.midY
        let adjusted = CGRect(
            x: workingRect.minX - 1,
            y: centerY - (targetHeight / 2),
            width: workingRect.width + 2,
            height: targetHeight
        )
        return adjusted.intersection(pageBounds)
    }

    static func previewColor(for category: String) -> NSColor {
        FindingVisualSemantics.nsColor(for: category)
    }

    static func makePreviewAnnotation(bounds: CGRect, category: String?) -> PDFAnnotation {
        let annotation = PreviewRedactionAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        annotation.border = nil
        if let category {
            annotation.tintColor = previewColor(for: category)
        }
        return annotation
    }

    static func makeRedactionAnnotation(
        bounds: CGRect,
        style: RedactionStyle,
        page: PDFPage,
        blurredImage: CGImage?
    ) -> PDFAnnotation {
        switch style {
        case .blackRectangle:
            let annotation = BlackRedactionAnnotation(bounds: bounds, forType: .square, withProperties: nil)
            annotation.border = nil
            return annotation
        case .blur:
            let annotation = BlurRedactionAnnotation(bounds: bounds, forType: .square, withProperties: nil)
            annotation.border = nil
            annotation.blurredPageImage = blurredImage
            annotation.pageMediaBoxRect = page.bounds(for: .mediaBox)
            return annotation
        }
    }
}

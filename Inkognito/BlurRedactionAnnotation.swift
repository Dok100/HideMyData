import AppKit
import Foundation
import PDFKit

nonisolated final class BlurRedactionAnnotation: PDFAnnotation {
    var blurredPageImage: CGImage?
    var pageMediaBoxRect: CGRect = .zero

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        if let blurredPageImage, !pageMediaBoxRect.isEmpty {
            drawBlurredContent(blurredPageImage, in: context)
        } else {
            drawFallbackFill(in: context)
        }
    }

    private func drawBlurredContent(_ image: CGImage, in context: CGContext) {
        context.saveGState()
        context.clip(to: bounds)
        context.draw(image, in: pageMediaBoxRect)
        context.restoreGState()
    }

    private func drawFallbackFill(in context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor(white: 0.55, alpha: 0.9).cgColor)
        context.fill(bounds)
        context.restoreGState()
    }
}

import Foundation
import PDFKit
import AppKit

nonisolated final class BlackRedactionAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
    }
}

nonisolated final class PreviewRedactionAnnotation: PDFAnnotation {
    var tintColor: NSColor = .systemOrange

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let fill = tintColor.withAlphaComponent(0.22).cgColor
        let stroke = tintColor.withAlphaComponent(0.85).cgColor

        context.saveGState()
        context.setFillColor(fill)
        context.fill(bounds)
        context.setStrokeColor(stroke)
        context.setLineWidth(2)
        context.stroke(bounds)
        context.restoreGState()
    }
}

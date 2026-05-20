import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit

enum RedactionRendering {
    static func gaussianBlurred(_ sharp: CGImage) -> CGImage? {
        let sharpCI = CIImage(cgImage: sharp)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = sharpCI
        blur.radius = Float(min(sharp.width, sharp.height)) * 0.02
        guard let blurredCI = blur.outputImage?.cropped(to: sharpCI.extent) else { return nil }
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        return ciContext.createCGImage(blurredCI, from: blurredCI.extent)
    }

    static func bakeImageRedactions(
        into image: CGImage,
        rects: [CGRect],
        style: RedactionStyle
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let flippedRects = rects.map { rect in
            CGRect(
                x: rect.minX,
                y: CGFloat(height) - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            .insetBy(dx: -2, dy: -2)
        }

        switch style {
        case .blackRectangle:
            ctx.setFillColor(NSColor.black.cgColor)
            for rect in flippedRects {
                ctx.fill(rect)
            }

        case .blur:
            guard let snapshot = ctx.makeImage(),
                  let blurred = gaussianBlurred(snapshot) else { return nil }
            for rect in flippedRects {
                ctx.saveGState()
                ctx.clip(to: rect)
                ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
                ctx.restoreGState()
            }
        }

        return ctx.makeImage()
    }

    static func renderPDFPageSnapshot(
        _ page: PDFPage,
        scale: CGFloat = 2.0,
        detaching annotations: [PDFAnnotation] = []
    ) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pixelWidth = Int(pageBounds.width * scale)
        let pixelHeight = Int(pageBounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        for annotation in annotations {
            page.removeAnnotation(annotation)
        }
        defer {
            for annotation in annotations {
                page.addAnnotation(annotation)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    static func bakePDFPage(
        _ page: PDFPage,
        rects: [CGRect],
        style: RedactionStyle,
        detaching annotations: [PDFAnnotation],
        scale: CGFloat = 2.0
    ) -> PDFPage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pixelWidth = Int(pageBounds.width * scale)
        let pixelHeight = Int(pageBounds.height * scale)
        guard pixelWidth > 0,
              pixelHeight > 0,
              let snapshot = renderPDFPageSnapshot(page, scale: scale, detaching: annotations) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(snapshot, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        let pixelRects = rects.map { rect in
            CGRect(
                x: rect.minX * scale,
                y: rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            .insetBy(dx: -2, dy: -2)
        }

        switch style {
        case .blackRectangle:
            ctx.setFillColor(NSColor.black.cgColor)
            for rect in pixelRects {
                ctx.fill(rect)
            }

        case .blur:
            guard let blurred = gaussianBlurred(snapshot) else { return nil }
            for rect in pixelRects {
                ctx.saveGState()
                ctx.clip(to: rect)
                ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                ctx.restoreGState()
            }
        }

        guard let finalCG = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: finalCG, size: pageBounds.size)
        return PDFPage(image: image)
    }
}

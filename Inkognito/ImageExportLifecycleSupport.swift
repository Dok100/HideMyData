import Foundation
import CoreGraphics
import ImageIO
internal import UniformTypeIdentifiers

enum ImageExportLifecycleResult {
    case success(RedactionExportResult)
    case failure(String)
}

enum ImageExportLifecycleSupport {
    static func writeRedactedImage(
        sourceImage cg: CGImage,
        destinationURL url: URL,
        uti: UTType,
        options: ExportOptions,
        redactionRects: [CGRect],
        redactionStyle: RedactionStyle,
        sourceImageProperties: [CFString: Any]?,
        manualRedactionCount: Int,
        detectionNotice: DocumentDetectionNotice?
    ) -> ImageExportLifecycleResult {
        guard let baked = RedactionRendering.bakeImageRedactions(
            into: cg,
            rects: redactionRects,
            style: redactionStyle
        ) else {
            return .failure("Das Bild konnte nicht exportiert werden, weil die Schwärzungen nicht sauber ins Bild eingebrannt werden konnten. Bitte versuche es erneut oder wähle einen anderen Speicherort.")
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti.identifier as CFString, 1, nil) else {
            return .failure("Für dieses Bildformat konnte kein Export-Ziel angelegt werden. Bitte versuche es erneut oder speichere als anderes Bildformat.")
        }
        CGImageDestinationAddImage(dest, baked, imageProperties(for: uti, options: options, sourceImageProperties: sourceImageProperties))
        guard CGImageDestinationFinalize(dest) else {
            return .failure("Das geschwärzte Bild konnte nicht am gewählten Ort gespeichert werden. Bitte prüfe Schreibrechte, freien Speicherplatz oder wähle einen anderen Speicherort.")
        }

        let report = ExportValidationReport(
            format: .image,
            redactionCount: redactionRects.count,
            manualRedactionCount: manualRedactionCount,
            redactedPageCount: nil,
            totalPageCount: nil,
            lowTextWarning: detectionNotice?.title.localizedCaseInsensitiveContains("lesbarer Text") == true
                || detectionNotice?.title.localizedCaseInsensitiveContains("OCR") == true,
            removedMetadata: options.removeMetadata,
            annotationsRemoved: true,
            bakedIntoPixels: !redactionRects.isEmpty
        )
        return .success(RedactionExportResult(url: url, report: report))
    }

    static func suggestedSaveName(sourceURL: URL?, uti: UTType) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "bild"
        let ext = uti.preferredFilenameExtension ?? "png"
        return "\(base)-geschwaerzt.\(ext)"
    }

    static func imageProperties(
        for uti: UTType,
        options: ExportOptions,
        sourceImageProperties: [CFString: Any]?
    ) -> CFDictionary? {
        var properties = options.removeMetadata ? [:] : sourceImageProperties ?? [:]
        properties[kCGImagePropertyOrientation] = 1

        if options.removeMetadata {
            if uti.conforms(to: .png) {
                properties[kCGImagePropertyPNGDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .jpeg) {
                properties[kCGImagePropertyJFIFDictionary] = [:] as CFDictionary
            } else if uti.conforms(to: .tiff) {
                properties[kCGImagePropertyTIFFDictionary] = [:] as CFDictionary
            }
        }

        return properties as CFDictionary
    }
}

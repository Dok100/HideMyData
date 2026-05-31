import CoreGraphics
import Foundation

enum ImagePreviewDiagnosticsSupport {
    static func lines(
        for findings: [ReviewFinding],
        previewRectEntries: [(rect: CGRect, findingID: UUID?)],
        page: OCRPage,
        pixelRectFromNormalized: (CGRect) -> CGRect
    ) -> [String] {
        var lines: [String] = []
        lines.append("Preview candidates: \(findings.count)")
        lines.append("Preview rects: \(previewRectEntries.count)")

        if findings.isEmpty {
            lines.append("Preview detail: <none>")
            return lines
        }

        for finding in findings {
            let rects = previewRectEntries
                .filter { $0.findingID == finding.id }
                .map(\.rect)
            let rectSummary = rects.enumerated().map { index, rect in
                "\(index): x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))"
            }.joined(separator: " | ")

            let matchedLineIndices = page.lines.enumerated().compactMap { index, _ -> Int? in
                guard let normalizedRect = page.normalizedLineBox(at: index) else { return nil }
                let lineRect = pixelRectFromNormalized(normalizedRect)
                return rects.contains(where: { rect in
                    let overlap = rect.intersection(lineRect)
                    guard !overlap.isNull else { return false }
                    let lineArea = max(lineRect.width * lineRect.height, 1)
                    return (overlap.width * overlap.height) / lineArea >= 0.4
                }) ? index : nil
            }

            let lineSummary = matchedLineIndices.map { index in
                "\(index): \(page.lines[index].text)"
            }.joined(separator: " | ")

            lines.append("[\(finding.category)] \(finding.snippet)")
            lines.append("  Source: \(finding.source.label) · \(Int(finding.confidence * 100))%")
            lines.append("  Rects: \(rectSummary.isEmpty ? "<none>" : rectSummary)")
            lines.append("  OCR lines: \(lineSummary.isEmpty ? "<none>" : lineSummary)")
        }

        return lines
    }
}

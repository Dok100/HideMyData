import CoreGraphics
import Foundation
import Vision

struct OCRLine {
    let text: String
    let candidate: RecognizedText
    let boundingBox: CGRect
}

struct OCRPage {
    let lines: [OCRLine]
    let combinedText: String
    private let lineStartOffsets: [Int]  // char offset in combinedText where each line starts

    init(lines: [OCRLine]) {
        self.lines = lines
        var combined = ""
        var starts: [Int] = []
        for (i, line) in lines.enumerated() {
            starts.append(combined.count)
            combined += line.text
            if i < lines.count - 1 { combined += "\n" }
        }
        self.combinedText = combined
        self.lineStartOffsets = starts
    }

    func normalizedBoxes(start: Int, end: Int) -> [CGRect] {
        guard start >= 0, end <= combinedText.count, start < end else { return [] }
        var rects: [CGRect] = []
        for (i, line) in lines.enumerated() {
            let lineStart = lineStartOffsets[i]
            let lineEnd = lineStart + line.text.count
            let lo = max(start, lineStart)
            let hi = min(end, lineEnd)
            guard lo < hi else { continue }

            let localStartOffset = lo - lineStart
            let localEndOffset = hi - lineStart
            let s = line.text.index(line.text.startIndex, offsetBy: localStartOffset)
            let e = line.text.index(line.text.startIndex, offsetBy: localEndOffset)
            if let region = line.candidate.boundingBox(for: s..<e) {
                rects.append(region.boundingBox.cgRect)
            } else if let fullLineRegion = line.candidate.boundingBox(for: line.text.startIndex..<line.text.endIndex) {
                rects.append(fullLineRegion.boundingBox.cgRect)
            } else {
                rects.append(line.boundingBox)
            }
        }
        return rects
    }

    func normalizedLineBox(at index: Int) -> CGRect? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index].boundingBox
    }

    func lineSpan(at index: Int, category: String, confidence: Float = 0.98, source: DetectionSource = .pattern) -> DetectedSpan? {
        guard lines.indices.contains(index) else { return nil }
        let line = lines[index]
        let cleaned = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let start = lineStartOffsets[index]
        let end = start + line.text.count
        return DetectedSpan(
            category: category,
            text: line.text,
            start: start,
            end: end,
            confidence: confidence,
            source: source
        )
    }

    func lineMatch(
        at index: Int,
        matchedText: String,
        category: String,
        confidence: Float = 0.98,
        source: DetectionSource = .pattern
    ) -> (span: DetectedSpan, rect: CGRect)? {
        guard lines.indices.contains(index) else { return nil }
        let line = lines[index]
        let trimmedMatch = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMatch.isEmpty,
              let localRange = line.text.range(of: trimmedMatch, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return nil
        }

        let start = lineStartOffsets[index] + line.text.distance(from: line.text.startIndex, to: localRange.lowerBound)
        let end = lineStartOffsets[index] + line.text.distance(from: line.text.startIndex, to: localRange.upperBound)
        let rect: CGRect
        if let region = line.candidate.boundingBox(for: localRange) {
            rect = region.boundingBox.cgRect
        } else if let fullLineRegion = line.candidate.boundingBox(for: line.text.startIndex..<line.text.endIndex) {
            rect = fullLineRegion.boundingBox.cgRect
        } else {
            rect = line.boundingBox
        }

        return (
            DetectedSpan(
                category: category,
                text: trimmedMatch,
                start: start,
                end: end,
                confidence: confidence,
                source: source
            ),
            rect
        )
    }

    func lineIndex(containing offset: Int) -> Int? {
        guard offset >= 0, offset < combinedText.count else { return nil }

        for (index, start) in lineStartOffsets.enumerated() {
            let end = start + lines[index].text.count
            if offset >= start && offset < end {
                return index
            }
        }

        return nil
    }
}

enum OCREngine {
    static func recognize(_ image: CGImage) async throws -> OCRPage {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image)
        let lines: [OCRLine] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return OCRLine(text: candidate.string, candidate: candidate, boundingBox: obs.boundingBox.cgRect)
        }
        return OCRPage(lines: lines)
    }
}

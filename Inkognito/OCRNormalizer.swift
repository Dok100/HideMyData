import Foundation

enum OCRNormalizer {
    enum Mode {
        case ocr
        case native
    }

    nonisolated static func normalize(_ text: String, mode: Mode = .ocr) -> (text: String, offsetMap: [Int]) {
        let chars = Array(text)
        var normalized = ""
        var map: [Int] = []
        var i = 0
        let isOCRMode: Bool
        switch mode {
        case .ocr:
            isOCRMode = true
        case .native:
            isOCRMode = false
        }
        while i < chars.count {
            if i + 2 < chars.count, chars[i] == " ", chars[i + 1] == "/", chars[i + 2] == " " {
                normalized.append("\n")
                map.append(i + 1)
                i += 3
            } else if isOCRMode, let run = spacedAlphaNumericRun(in: chars, from: i) {
                for index in run.characterIndices {
                    normalized.append(chars[index])
                    map.append(index)
                }
                i = run.nextIndex
            } else if isOCRMode, chars[i] == " ", shouldDropSpace(in: chars, at: i) {
                i += 1
            } else {
                normalized.append(chars[i])
                map.append(i)
                i += 1
            }
        }
        return (normalized, map)
    }

    nonisolated private static func spacedAlphaNumericRun(in chars: [Character], from start: Int) -> (characterIndices: [Int], nextIndex: Int)? {
        guard start + 2 < chars.count,
              chars[start].isLetter || chars[start].isNumber,
              chars[start + 1] == " ",
              chars[start + 2].isLetter || chars[start + 2].isNumber
        else {
            return nil
        }

        var indices = [start]
        var cursor = start
        while cursor + 2 < chars.count,
              chars[cursor + 1] == " ",
              chars[cursor + 2].isLetter || chars[cursor + 2].isNumber {
            indices.append(cursor + 2)
            cursor += 2
        }

        // Only collapse true OCR-style spaced runs like "O e d h e i m".
        // A single normal word boundary like "Sylvia Friedenstr." must stay intact.
        guard indices.count >= 3 else { return nil }
        return (indices, cursor + 1)
    }

    nonisolated private static func shouldDropSpace(in chars: [Character], at index: Int) -> Bool {
        guard index > 0, index + 1 < chars.count else { return false }
        let previous = chars[index - 1]
        let next = chars[index + 1]

        if previous.isNumber && next.isNumber {
            return true
        }

        let punctuation = CharacterSet(charactersIn: ".,:/-")
        if previous.isNumber,
           next.unicodeScalars.allSatisfy({ punctuation.contains($0) }),
           index + 2 < chars.count,
           chars[index + 2].isNumber {
            return true
        }
        if next.isNumber,
           previous.unicodeScalars.allSatisfy({ punctuation.contains($0) }),
           index > 1,
           chars[index - 2].isNumber {
            return true
        }

        return false
    }

    nonisolated static func translateRange(start: Int, end: Int, map: [Int], originalCount: Int) -> (start: Int, end: Int) {
        guard !map.isEmpty else { return (start, end) }
        let s = (start >= 0 && start < map.count) ? map[start] : originalCount
        let e = (end > 0 && end <= map.count) ? (map[end - 1] + 1) : originalCount
        return (s, e)
    }
}

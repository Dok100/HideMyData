import Foundation

enum DetectionRegressionFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

enum OCRMode {
    case ocr
    case native
}

func normalizeOCRText(_ text: String, mode: OCRMode) -> String {
    let chars = Array(text)
    var normalized = ""
    var i = 0
    let isOCRMode = mode == .ocr

    while i < chars.count {
        if i + 2 < chars.count, chars[i] == " ", chars[i + 1] == "/", chars[i + 2] == " " {
            normalized.append("\n")
            i += 3
        } else if isOCRMode, let run = spacedAlphaNumericRun(in: chars, from: i) {
            for index in run.characterIndices {
                normalized.append(chars[index])
            }
            i = run.nextIndex
        } else if isOCRMode, chars[i] == " ", shouldDropSpace(in: chars, at: i) {
            i += 1
        } else {
            normalized.append(chars[i])
            i += 1
        }
    }

    return normalized
}

func spacedAlphaNumericRun(in chars: [Character], from start: Int) -> (characterIndices: [Int], nextIndex: Int)? {
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

    guard indices.count >= 3 else { return nil }
    return (indices, cursor + 1)
}

func shouldDropSpace(in chars: [Character], at index: Int) -> Bool {
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

func shouldSuppressHeaderLikeFinding(snippet: String, category: String, pageText: String) -> Bool {
    let cleanedSnippet = snippet
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedSnippet.isEmpty else { return false }

    let isPostalCity = cleanedSnippet.range(
        of: #"^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#,
        options: .regularExpression
    ) != nil
    let isBareCityToken = category == "private_person" &&
        cleanedSnippet.range(of: #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]{3,}$"#, options: .regularExpression) != nil
    let isStreetAddress = category == "private_address" && looksLikeGermanStreetAddress(cleanedSnippet)
    let isLikelyPersonName = category == "private_person" &&
        cleanedSnippet.range(
            of: #"(?i)^(?:herr|frau)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}$|^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}(?:,\s*(?:CEO|CFO|COO|CTO|CMO))?$"#,
            options: .regularExpression
        ) != nil
    guard isPostalCity || isBareCityToken || isStreetAddress || isLikelyPersonName else { return false }

    let normalizedSnippet = cleanedSnippet.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let lines = pageText.components(separatedBy: .newlines)
    let headerKeywords = [
        "finanzamt", "finanzkasse", "moltkestr", "moltkestra", "tel", "zi.nr",
        "steuernummer", "idnr", "deutsche post", "geschäftsführung",
        "geschaftsfuhrung", "geschäftsführer", "geschaftsfuhrer",
        "handelsregister", "amtsgericht", "bankverbindung", "onlinebuchung",
        "reisebestätigung", "reisebestatigung"
    ]

    for (index, line) in lines.enumerated() {
        let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) else { continue }

        if (isPostalCity || isStreetAddress) && looksLikeOrganizationSnippet(line) {
            return true
        }

        let contextStart = max(0, index - 2)
        let contextEnd = min(lines.count - 1, index + 2)
        let context = lines[contextStart...contextEnd]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if headerKeywords.contains(where: { context.contains($0) }) {
            return true
        }
        if isLikelyPersonName,
           context.contains("geschäftsführung") || context.contains("geschaftsfuhrung") ||
            context.contains("ceo") || context.contains("cfo") ||
            context.contains("geschäftsführer") || context.contains("geschaftsfuhrer") {
            return true
        }
        if isPostalCity,
           context.range(of: #"\b\d{2}\.\d{2}\.\d{4}\b"#, options: .regularExpression) != nil {
            return true
        }
        if isPostalCity,
           context.range(of: #"\(?\d{3,5}\)?[ /-]?\d{2,5}[-/]\d{2,5}"#, options: .regularExpression) != nil {
            return true
        }
    }

    return false
}

func shouldDropModelAccountNumber(_ text: String) -> Bool {
    let digitsOnly = text.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
    let hasLetters = text.rangeOfCharacter(from: .letters) != nil
    return !hasLetters && digitsOnly.count < 12
}

func normalizedComparableText(_ text: String) -> String {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .filter { $0.isLetter || $0.isNumber }
}

func looksLikeOrganizationSnippet(_ text: String) -> Bool {
    text.range(of: #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#, options: .regularExpression) != nil
}

func looksLikePostalCity(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.range(
        of: #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#,
        options: .regularExpression
    ) != nil
}

func looksLikeGermanStreetAddress(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.range(
        of: #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#,
        options: .regularExpression
    ) != nil
}

func hasLeadingSentenceFragmentBeforeStreetAddress(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard looksLikeGermanStreetAddress(cleaned) else { return false }

    return cleaned.range(
        of: #"(?i)^.+[.!?:]\s+(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#,
        options: .regularExpression
    ) != nil
}

func looksLikeCompanyAddressBlock(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard looksLikeOrganizationSnippet(cleaned) else { return false }
    return looksLikeGermanStreetAddress(cleaned) ||
        looksLikePostalCity(cleaned) ||
        cleaned.range(of: #"\b\d+[A-Za-z]?\b"#, options: .regularExpression) != nil
}

func extractInlineContextPersonName(_ text: String) -> String? {
    let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let pattern = #"(?i)\b(?:name|bestellt\s+durch|besteller(?:in)?|kund(?:e|in)|kontoinhaber)\s*:\s*([A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)?\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    guard let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: normalized) else {
        return nil
    }
    return String(normalized[range])
}

func extractSalutationPersonName(_ text: String) -> String? {
    let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    let patterns = [
        #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
        #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}\s+und\s+(?:Herr|Frau)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#,
        #"(?i)\b(?:sehr\s+geehrte[rsn]?|guten\s+tag|guten\s+morgen|guten\s+abend|hallo|liebe|lieber)\s+((?:Frau|Herr)\s+(?:(?:Dr|Prof)\.?\s+)?[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2})\b"#
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: normalized)
        else { continue }
        return String(normalized[range]).trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
    }
    return nil
}

func deduplicatedLabeledAddressBlock(after label: String, in text: String) -> [String] {
    let lines = text.components(separatedBy: .newlines)
    guard let labelIndex = lines.firstIndex(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains(label)
    }) else {
        return []
    }

    var values: [String] = []
    var previousComparable = ""
    let searchEnd = min(lines.count, labelIndex + 8)
    for index in (labelIndex + 1)..<searchEnd {
        let cleaned = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { continue }
        let comparable = normalizedComparableText(cleaned)
        if comparable == previousComparable, !comparable.isEmpty { continue }
        values.append(cleaned)
        previousComparable = comparable
        if looksLikePostalCity(cleaned) { break }
    }
    return values
}

func preservesStrongCustomIdentifier(_ candidate: String) -> Bool {
    let normalizedCandidate = normalizedComparableText(candidate)
    guard !normalizedCandidate.isEmpty else { return false }
    if candidate.rangeOfCharacter(from: .decimalDigits) != nil {
        return false
    }
    let tokenCount = candidate
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: \.isWhitespace)
        .count
    return tokenCount >= 2
}

func personSpanContainsAddressOrContactTail(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedText = normalizedComparableText(cleaned)
    guard normalizedText.contains("frau") || normalizedText.contains("herr") else { return false }

    if looksLikeGermanStreetAddress(cleaned) {
        return true
    }

    let bannedFragments = [
        "email", "telefon", "mobil", "kontakt", "ansprechpartner",
        "strasse", "straße", "str", "weg", "allee", "platz", "gasse", "ring", "ufer", "steig", "steige"
    ]
    return bannedFragments.contains { fragment in
        cleaned.localizedCaseInsensitiveContains(fragment) || normalizedText.contains(normalizedComparableText(fragment))
    }
}

func firstMatch(for pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let swiftRange = Range(match.range, in: text) else {
        return nil
    }
    return String(text[swiftRange])
}

func shouldSuppressSenderLikeFinding(snippet: String, category: String, pageText: String) -> Bool {
    let cleanedSnippet = snippet
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedSnippet.isEmpty else { return false }

    let normalizedSnippet = cleanedSnippet.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let compactSnippet = normalizedComparableText(cleanedSnippet)

    let isPostalCity = looksLikePostalCity(cleanedSnippet)
    let isStreetAddress = category == "private_address" && looksLikeGermanStreetAddress(cleanedSnippet)
    let isBareCityToken = category == "private_person" &&
        compactSnippet.range(of: #"^[a-zäöüß]{4,}$"#, options: .regularExpression) != nil
    guard isPostalCity || isStreetAddress || isBareCityToken else { return false }

    let lines = pageText.components(separatedBy: .newlines)
    let senderKeywords = ["gmbh", "mbh", "ag", "ug", "kg", "ohg", "gbr", "kundin", "kunde"]
    let companyHeaderPresent = lines.prefix(6).contains { line in
        let normalized = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return senderKeywords.contains(where: { normalized.contains($0) })
    }
    let firstRecipientIndex = lines.firstIndex { line in
        looksLikeRecipientMarkerLine(line)
    }

    for (index, line) in lines.enumerated() {
        let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let compactLine = normalizedComparableText(normalizedLine)
        guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) ||
                (!compactSnippet.isEmpty && compactLine.contains(compactSnippet))
        else { continue }

        let contextStart = max(0, index - 2)
        let contextEnd = min(lines.count - 1, index + 2)
        let context = lines[contextStart...contextEnd]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if let firstRecipientIndex,
           index < firstRecipientIndex,
           senderKeywords.contains(where: { context.contains($0) }) {
            return true
        }
        if companyHeaderPresent,
           isEmbeddedSenderBlockLine(in: lines, at: index, isStreetAddress: isStreetAddress, isPostalCity: isPostalCity) {
            return true
        }
    }

    return false
}

func isEmbeddedSenderBlockLine(in lines: [String], at index: Int, isStreetAddress: Bool, isPostalCity: Bool) -> Bool {
    guard index >= 0, index < lines.count else { return false }

    let previousIndex = nearestNonEmptyLineIndex(in: lines, before: index)
    let nextIndex = nearestNonEmptyLineIndex(in: lines, after: index)
    let hasRecipientMarkerNearby = (max(0, index - 2)...min(lines.count - 1, index + 1)).contains { nearbyIndex in
        looksLikeRecipientMarkerLine(lines[nearbyIndex])
    }
    guard !hasRecipientMarkerNearby else { return false }

    let senderContextKeywords = ["vertrieb", "kundenservice", "kontakt", "tarif", "online", "gmbh", "ag", "mbh"]
    let previousLine = previousIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    let normalizedPrevious = previousLine.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let previousLooksSenderLike =
        previousLine.contains(".") ||
        previousLine.contains(":") ||
        senderContextKeywords.contains(where: { normalizedPrevious.contains($0) })

    if isStreetAddress,
       let nextIndex,
       looksLikePostalCity(lines[nextIndex]),
       previousLooksSenderLike {
        return true
    }

    if isPostalCity,
       let previousIndex,
       looksLikeGermanStreetAddress(lines[previousIndex]) {
        let senderPreludeIndex = nearestNonEmptyLineIndex(in: lines, before: previousIndex)
        let senderPrelude = senderPreludeIndex.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let normalizedPrelude = senderPrelude.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if senderPrelude.contains(".") ||
            senderPrelude.contains(":") ||
            senderContextKeywords.contains(where: { normalizedPrelude.contains($0) }) {
            return true
        }
    }

    return false
}

func nearestNonEmptyLineIndex(in lines: [String], before index: Int) -> Int? {
    guard index > 0 else { return nil }
    for candidate in stride(from: index - 1, through: 0, by: -1) {
        if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidate
        }
    }
    return nil
}

func nearestNonEmptyLineIndex(in lines: [String], after index: Int) -> Int? {
    guard index + 1 < lines.count else { return nil }
    for candidate in (index + 1)..<lines.count {
        if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidate
        }
    }
    return nil
}

func looksLikeRecipientMarkerLine(_ line: String) -> Bool {
    let cleaned = line
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return false }

    let explicitPrefixes = [
        "kundin:", "kunde:", "lieferadresse:", "schriftverkehr", "kontoinhaber:", "abweichender ansprechpartner:",
        "bestellt durch:", "besteller:", "bestellerin:", "name:"
    ]
    return explicitPrefixes.contains(where: { cleaned.hasPrefix($0) })
}

func looksLikeHonorificStreetCombo(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !looksLikePostalCity(cleaned),
          looksLikeGermanStreetAddress(cleaned)
    else { return false }

    let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
    return cleaned.range(of: pattern, options: .regularExpression) != nil
}

func looksLikeLeadingConjunctionAddressTail(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard looksLikeGermanStreetAddress(cleaned) else { return false }

    let pattern = #"(?i)^und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
    return cleaned.range(of: pattern, options: .regularExpression) != nil
}

func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw DetectionRegressionFailure.failed(message)
    }
}

struct FixtureCase {
    let documentClass: String
    let fixturePath: String
    let checks: [(String, (String) throws -> Void)]
}

func fixture(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
}

func expectContains(_ expected: String) -> (String) throws -> Void {
    { text in
        try assert(text.contains(expected), "Expected fixture to contain '\(expected)'")
    }
}

func expectHeaderSuppressed(snippet: String, category: String) -> (String) throws -> Void {
    { text in
        try assert(
            shouldSuppressHeaderLikeFinding(snippet: snippet, category: category, pageText: text),
            "Expected header-like \(category) snippet '\(snippet)' to be suppressed"
        )
    }
}

func expectHeaderRetained(snippet: String, category: String) -> (String) throws -> Void {
    { text in
        try assert(
            !shouldSuppressHeaderLikeFinding(snippet: snippet, category: category, pageText: text),
            "Expected legitimate \(category) snippet '\(snippet)' to remain"
        )
    }
}

func expectSenderSuppressed(snippet: String, category: String) -> (String) throws -> Void {
    { text in
        try assert(
            shouldSuppressSenderLikeFinding(snippet: snippet, category: category, pageText: text),
            "Expected sender-like \(category) snippet '\(snippet)' to be suppressed"
        )
    }
}

func expectRegexMatch(_ pattern: String, equals expected: String) -> (String) throws -> Void {
    { text in
        try assert(
            firstMatch(for: pattern, in: text) == expected,
            "Expected regex \(pattern) to extract '\(expected)'"
        )
    }
}

func expectRegexNoMatch(_ pattern: String, forbidden: String) -> (String) throws -> Void {
    { text in
        try assert(
            firstMatch(for: pattern, in: text) != forbidden,
            "Expected regex \(pattern) not to emit '\(forbidden)'"
        )
    }
}

func runFixtureCases() throws -> Int {
    let germanPostalCityPattern = #"(?i)\b\d{5}[ \t]*(?:\n[ \t]*)?(?!(?:Amazon|Bestell|Rechnung|Deutschland|Kontakt|Fax|Geschäftsführer|Registergericht|Kunden|Menge|Lieferung|Lieferadresse)\b)[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}\b(?!<)"#
    let tightenedGermanPostalCityPattern = #"(?i)\b\d{5}[ \t]*(?:\n[ \t]*)?(?!(?:Amazon|Bestell|Rechnung|Deutschland|Kontakt|Fax|Geschäftsführer|Registergericht|Kunden|Menge|Lieferung|Lieferadresse|Seite|Steuer(?:-Nr)?|Vorsitzender|Datum|Ersetzt)\b)[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}\b(?!<)"#
    let cases: [FixtureCase] = [
        FixtureCase(
            documentClass: "Steuerbescheid / OCR",
            fixturePath: "fixtures/detection/steuerbescheid_page1_ocr.txt",
            checks: [
                ("Suppress briefkopf postal city", expectHeaderSuppressed(snippet: "73084 Falkenstadt", category: "private_address")),
                ("Suppress window-address city", expectHeaderSuppressed(snippet: "73086 Falkenstadt", category: "private_address")),
                ("Suppress bare city token", expectHeaderSuppressed(snippet: "Falkenstadt", category: "private_person")),
                ("Retain recipient postal city", expectHeaderRetained(snippet: "74523 Lindenheim", category: "private_address"))
            ]
        ),
        FixtureCase(
            documentClass: "Inkasso / OCR",
            fixturePath: "fixtures/detection/inkasso_ocr_text.txt",
            checks: [
                ("Fixture contains salutation", expectContains("Sehr geehrte Frau Vogt,")),
                ("Keep recipient postal city", expectContains("74223 Steinbach")),
                ("Extract salutation honorific name", { text in
                    try assert(extractSalutationPersonName(text) == "Frau Vogt", "Expected salutation line to expose the honorific surname")
                })
            ]
        ),
        FixtureCase(
            documentClass: "Inkasso / OCR Folgebrief",
            fixturePath: "fixtures/detection/inkasso_ocr_text_followup.txt",
            checks: [
                ("Fixture contains salutation", expectContains("Sehr geehrte Frau Vogt,")),
                ("Keep recipient postal city", expectContains("74223 Steinbach")),
                ("Extract salutation honorific name", { text in
                    try assert(extractSalutationPersonName(text) == "Frau Vogt", "Expected follow-up salutation line to expose the honorific surname")
                })
            ]
        ),
        FixtureCase(
            documentClass: "Rechnung / Lieferanschrift Alias",
            fixturePath: "fixtures/detection/lieferanschrift_alias_native_pdf_text.txt",
            checks: [
                ("Fixture contains Lieferanschrift label", expectContains("Lieferanschrift:")),
                ("Fixture contains duplicated recipient name", expectContains("Jonas Weber")),
                ("Fixture contains distinct delivery street", expectContains("Birkenweg 12")),
                ("Resolve delivery recipient name after Lieferanschrift", { text in
                    let block = deduplicatedLabeledAddressBlock(after: "Lieferanschrift:", in: text)
                    try assert(block.contains("Jonas Weber"), "Expected Lieferanschrift alias block to preserve the recipient name line")
                }),
                ("Resolve delivery street after Lieferanschrift", { text in
                    let block = deduplicatedLabeledAddressBlock(after: "Lieferanschrift:", in: text)
                    try assert(block.contains("Birkenweg 12"), "Expected Lieferanschrift alias block to expose its own street line")
                }),
                ("Resolve delivery postal city after Lieferanschrift", { text in
                    let block = deduplicatedLabeledAddressBlock(after: "Lieferanschrift:", in: text)
                    try assert(block.contains("74229 Sommerfeld"), "Expected Lieferanschrift alias block to expose its own postal city")
                })
            ]
        ),
        FixtureCase(
            documentClass: "Anrede / Guten Tag Varianten",
            fixturePath: "fixtures/detection/salutation_guten_tag_variants_text.txt",
            checks: [
                ("Fixture contains Guten Tag Herr", expectContains("Guten Tag Herr Kern,")),
                ("Extract Guten Tag Herr", { _ in
                    try assert(extractSalutationPersonName("Guten Tag Herr Kern,") == "Herr Kern", "Expected 'Guten Tag Herr ...' to expose the honorific name")
                }),
                ("Extract Guten Tag Frau", { _ in
                    try assert(extractSalutationPersonName("Guten Tag Frau Leitz,") == "Frau Leitz", "Expected 'Guten Tag Frau ...' to expose the honorific name")
                }),
                ("Extract Guten Tag Herr und Frau", { _ in
                    try assert(extractSalutationPersonName("Guten Tag Herr und Frau Kern,") == "Herr und Frau Kern", "Expected shared-surname pair salutation to be exposed")
                }),
                ("Extract Guten Tag paired full names", { _ in
                    try assert(extractSalutationPersonName("Guten Tag Herr Kern und Frau Kern,") == "Herr Kern und Frau Kern", "Expected paired salutation to be exposed")
                }),
                ("Extract Hallo Frau", { _ in
                    try assert(extractSalutationPersonName("Hallo Frau Leitz,") == "Frau Leitz", "Expected 'Hallo Frau ...' to expose the honorific name")
                }),
                ("Extract Guten Morgen Herr", { _ in
                    try assert(extractSalutationPersonName("Guten Morgen Herr Kern,") == "Herr Kern", "Expected 'Guten Morgen Herr ...' to expose the honorific name")
                }),
                ("Extract Guten Abend Frau", { _ in
                    try assert(extractSalutationPersonName("Guten Abend Frau Leitz,") == "Frau Leitz", "Expected 'Guten Abend Frau ...' to expose the honorific name")
                }),
                ("Extract Liebe Frau", { _ in
                    try assert(extractSalutationPersonName("Liebe Frau Leitz,") == "Frau Leitz", "Expected 'Liebe Frau ...' to expose the honorific name")
                }),
                ("Extract Lieber Herr", { _ in
                    try assert(extractSalutationPersonName("Lieber Herr Kern,") == "Herr Kern", "Expected 'Lieber Herr ...' to expose the honorific name")
                })
            ]
        ),
        FixtureCase(
            documentClass: "Formular / OCR Adresslabels",
            fixturePath: "fixtures/detection/formular_adresslabels_ocr.txt",
            checks: [
                ("Fixture contains street label", expectContains("Straße: Weinbergsteige")),
                ("Fixture contains house-number label", expectContains("Hausnr.: 3")),
                ("Keep labeled street", expectContains("Weinbergsteige")),
                ("Keep labeled postal code", expectContains("74223")),
                ("Keep labeled city", expectContains("Flein bei Heilbronn"))
            ]
        ),
        FixtureCase(
            documentClass: "Formular / OCR Adresslabels getrennt",
            fixturePath: "fixtures/detection/formular_adresslabels_ocr_split.txt",
            checks: [
                ("Fixture contains split street label", expectContains("Straße:")),
                ("Fixture contains split city value", expectContains("Flein bei Heilbronn")),
                ("Keep split street value", expectContains("Weinbergsteige")),
                ("Keep split postal code", expectContains("74223")),
                ("Keep split city value", expectContains("Flein bei Heilbronn"))
            ]
        ),
        FixtureCase(
            documentClass: "Behoerdenbrief / nativer PDF-Text",
            fixturePath: "fixtures/detection/behoerdenbrief_bescheid_native_pdf_text.txt",
            checks: [
                ("Suppress authority postal city", expectHeaderSuppressed(snippet: "41061 Rheindorf", category: "private_address")),
                ("Suppress authority city token", expectHeaderSuppressed(snippet: "Rheindorf", category: "private_person")),
                ("Retain recipient postal city", expectHeaderRetained(snippet: "24576 Heidefeld", category: "private_address"))
            ]
        ),
        FixtureCase(
            documentClass: "Rechnung / Absenderblock",
            fixturePath: "fixtures/detection/rechnung_senderblock_pdf_text.txt",
            checks: [
                ("Fixture contains contact-label context", expectContains("Abweichender Ansprechpartner:")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Musterweg 88", category: "private_address")),
                ("Suppress sender city token", expectSenderSuppressed(snippet: "Mon<heim", category: "private_person")),
                ("Avoid partial sender city regex hit", expectRegexNoMatch(germanPostalCityPattern, forbidden: "70173 Stu")),
                ("Avoid page-number postal city regex hit", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "03086 Seite")),
                ("Extract Kundennummer", expectRegexMatch(#"(?<=\bKundennummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "120034854")),
                ("Extract Vertragsnummer", expectRegexMatch(#"(?<=\bVertragsnummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "ES-2026-004281")),
                ("Extract Zählernummer", expectRegexMatch(#"(?<=\b(?:Zählernummer|Zaehlernummer):\s)\d{6,}\b"#, equals: "341939022")),
                ("Extract Vorgangsnummer", expectRegexMatch(#"(?<=\bVorgangsnummer:\s)\d{6,}\b"#, equals: "501075621"))
            ]
        ),
        FixtureCase(
            documentClass: "Rechnung / E-Commerce",
            fixturePath: "fixtures/detection/elektrowelt24_rechnung_native_pdf_text.txt",
            checks: [
                ("Fixture contains orderer label", expectContains("Bestellt durch: Jonas Weber")),
                ("Keep recipient street", expectContains("Gartenstraße 25")),
                ("Keep recipient postal city", expectContains("74229 Sommerfeld")),
                ("Extract ordered-by name", { text in
                    try assert(extractInlineContextPersonName(text) == "Jonas Weber", "Expected inline 'Bestellt durch' name to be extracted")
                })
            ]
        ),
        FixtureCase(
            documentClass: "Formular / Namenslabels",
            fixturePath: "fixtures/detection/name_label_varianten_native_pdf_text.txt",
            checks: [
                ("Fixture contains generic name label", expectContains("Name: Kern Oliver")),
                ("Fixture contains orderer label", expectContains("Bestellt durch: Jonas Weber")),
                ("Fixture contains account-holder label", expectContains("Kontoinhaber: Winter Paula")),
                ("Extract reversed name from Name label", { text in
                    try assert(extractInlineContextPersonName(text) == "Kern Oliver", "Expected inline 'Name' label to accept reversed order")
                }),
                ("Keep reversed recipient block postal city", expectContains("12345 Beispielstadt"))
            ]
        ),
        FixtureCase(
            documentClass: "Rechnung / Bankseite",
            fixturePath: "fixtures/detection/rechnung_bankdaten_page2_pdf_text.txt",
            checks: [
                ("Extract BIC", expectRegexMatch(#"(?<=\bBIC:\s)[A-Z0-9]{8}(?:[A-Z0-9]{3})?\b"#, equals: "TESTDEFFXXX")),
                ("Avoid IBAN-BIC merged regex hit", expectRegexNoMatch(#"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]){10,30}\b(?!\s*BIC\b)"#, forbidden: "DE30200300000010187201 BIC")),
                ("Keep recipient address context", expectContains("24576 Heidefeld")),
                ("Keep account holder context", expectContains("Kontoinhaber: Lena Sommer"))
            ]
        ),
        FixtureCase(
            documentClass: "Bank / Girokonto-Labels",
            fixturePath: "fixtures/detection/girokonto_labels_native_pdf_text.txt",
            checks: [
                ("Fixture contains girokonto label", expectContains("Girokonto 4287314")),
                ("Fixture contains girokontonummer label", expectContains("Girokontonummer: 4 287 314")),
                ("Extract Girokonto without colon", expectRegexMatch(#"(?:(?<=\bGirokonto:\s)|(?<=\bGirokonto\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "4287314")),
                ("Extract Girokontonummer with colon", expectRegexMatch(#"(?:(?<=\bGirokontonummer:\s)|(?<=\bGirokontonummer\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "4 287 314"))
            ]
        ),
        FixtureCase(
            documentClass: "Bank / Girokonto Screenshot-Variante",
            fixturePath: "fixtures/detection/girokonto_screenshot_variant_native_pdf_text.txt",
            checks: [
                ("Fixture contains girokonto screenshot label", expectContains("Girokonto 2754096,")),
                ("Extract Girokonto field before adjacent IBAN", expectRegexMatch(#"\bGirokonto\s*:?\s*(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "Girokonto 2754096")),
                ("Extract Girokonto before trailing comma", expectRegexMatch(#"(?:(?<=\bGirokonto:\s)|(?<=\bGirokonto\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "2754096")),
                ("Extract Girokontonummer field without colon", expectRegexMatch(#"\bGirokontonummer\s*:?\s*(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "Girokontonummer 2 754 096")),
                ("Extract Girokontonummer without colon", expectRegexMatch(#"(?:(?<=\bGirokontonummer:\s)|(?<=\bGirokontonummer\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "2 754 096")),
                ("Extract Kontonummer field with colon", expectRegexMatch(#"\bKontonummer\s*:?\s*(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "Kontonummer: 2754096")),
                ("Extract Kontonummer with colon", expectRegexMatch(#"(?:(?<=\bKontonummer:\s)|(?<=\bKontonummer\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "2754096"))
            ]
        ),
        FixtureCase(
            documentClass: "Kontakt- und Bankseite",
            fixturePath: "fixtures/detection/kontaktdaten_bankseite_pdf_text.txt",
            checks: [
                ("Extract couple name", expectRegexMatch(#"\b[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#, equals: "Milan und Lara Sommer")),
                ("Extract BLZ", expectRegexMatch(#"(?<=\bBLZ\s)\d{8}\b"#, equals: "62050000")),
                ("Extract Konto", expectRegexMatch(#"(?:(?<=\bKonto:\s)|(?<=\bKonto\s))(?:\d{5,}|\d{1,}(?:\s\d{2,})+)\b"#, equals: "2754096"))
            ]
        ),
        FixtureCase(
            documentClass: "Formular / standardisiertes Schreiben",
            fixturePath: "fixtures/detection/formular_kundendaten_pdf_text.txt",
            checks: [
                ("Suppress service sender street", expectSenderSuppressed(snippet: "Musterweg 9", category: "private_address")),
                ("Suppress service sender city token", expectSenderSuppressed(snippet: "Rheinhafen", category: "private_person")),
                ("Keep honorific name context", expectContains("Frau Paula Winter")),
                ("Keep street address context", expectContains("Ahornweg 21")),
                ("Keep postal city context", expectContains("24589 Lindenried")),
                ("Extract BIC", expectRegexMatch(#"(?<=\bBIC:\s)[A-Z0-9]{8}(?:[A-Z0-9]{3})?\b"#, equals: "TESTDEFF500")),
                ("Extract Kundennummer", expectRegexMatch(#"(?<=\bKundennummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "KD-2026-00981")),
                ("Extract Vertragsnummer", expectRegexMatch(#"(?<=\bVertragsnummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "SD-2026-0042"))
            ]
        ),
        FixtureCase(
            documentClass: "Energieversorger / Vertragsbrief",
            fixturePath: "fixtures/detection/energieversorger_vertragsbrief_native_pdf_text.txt",
            checks: [
                ("Fixture contains recipient context", expectContains("Eheleute")),
                ("Fixture contains contact-label context", expectContains("Hier erreichen wir Sie bei Rückfragen:")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Adolf-Pirrung-Str. 7", category: "private_address")),
                ("Suppress sender postal city", expectSenderSuppressed(snippet: "88400 Biberach", category: "private_address")),
                ("Avoid footer postal fragment from Steuer-Nr", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "19122 Steuer-Nr")),
                ("Avoid footer postal fragment from Aufsichtsratskontext", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "01075 Vorsitzender")),
                ("Keep recipient couple name", expectContains("Jonas und Nina Weber")),
                ("Keep billing street", expectContains("Gartenstr. 25")),
                ("Keep billing postal city", expectContains("74229 Sommerfeld"))
            ]
        ),
        FixtureCase(
            documentClass: "Stadtwerke / Vertragsbrief",
            fixturePath: "fixtures/detection/stadtwerke_vertragsbrief_native_pdf_text.txt",
            checks: [
                ("Fixture contains contact-label context", expectContains("Ihr Ansprechpartner bei Rückfragen:")),
                ("Fixture contains Lieferstelle label", expectContains("Lieferstelle")),
                ("Fixture contains Rechnungsanschrift label", expectContains("Rechnungsanschrift")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Hafenweg 14", category: "private_address")),
                ("Suppress sender postal city", expectSenderSuppressed(snippet: "27568 Nordtal", category: "private_address")),
                ("Avoid footer postal fragment from Steuer-Nr", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "08151 Vorsitzender")),
                ("Keep contact name", expectContains("Lena und Paul Sommer")),
                ("Keep delivery street", expectContains("Birkenweg 12")),
                ("Keep delivery postal city", expectContains("27574 Süderhafen"))
            ]
        ),
        FixtureCase(
            documentClass: "Versicherung / Vertragsbrief",
            fixturePath: "fixtures/detection/versicherung_vertragsbrief_native_pdf_text.txt",
            checks: [
                ("Fixture contains Versicherungsnehmer label", expectContains("Versicherungsnehmer")),
                ("Fixture contains Postanschrift label", expectContains("Postanschrift")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Hafenallee 9", category: "private_address")),
                ("Suppress sender postal city", expectSenderSuppressed(snippet: "28195 Weserbrück", category: "private_address")),
                ("Avoid footer postal fragment from Steuer-Nr", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "09111 Vorsitzender")),
                ("Keep policyholder name", expectContains("Laura und Tim Berger")),
                ("Keep policyholder street", expectContains("Lindenweg 4")),
                ("Keep policyholder postal city", expectContains("24589 Lindenried"))
            ]
        ),
        FixtureCase(
            documentClass: "Bank / Darlehensbrief",
            fixturePath: "fixtures/detection/bank_darlehensbrief_native_pdf_text.txt",
            checks: [
                ("Fixture contains Darlehensnehmer label", expectContains("Darlehensnehmer")),
                ("Fixture contains Korrespondenzanschrift label", expectContains("Korrespondenzanschrift")),
                ("Fixture contains Objektanschrift label", expectContains("Objektanschrift")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Marktstraße 17", category: "private_address")),
                ("Suppress sender postal city", expectSenderSuppressed(snippet: "60311 Mainhafen", category: "private_address")),
                ("Avoid footer postal fragment from Steuer-Nr", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "10121 Vorsitzender")),
                ("Keep borrower name", expectContains("Jonas und Mira Feld")),
                ("Keep borrower street", expectContains("Ahornweg 18")),
                ("Keep borrower postal city", expectContains("60389 Mainhafen"))
            ]
        ),
        FixtureCase(
            documentClass: "Reisebestätigung / Rechnung",
            fixturePath: "fixtures/detection/reisebestaetigung_rechnung_native_pdf_text.txt",
            checks: [
                ("Fixture contains recipient honorific line", expectContains("Herr\nHelmut Knobel")),
                ("Fixture contains participant section", expectContains("1. Herr Knobel/Helmut")),
                ("Suppress company header postal city", expectHeaderSuppressed(snippet: "20097 Hamburg", category: "private_address")),
                ("Suppress inline date postal fragment", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "54356 Datum")),
                ("Suppress footer postal fragment from replacement note", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "00052 Ersetzt")),
                ("Suppress management person", expectHeaderSuppressed(snippet: "Wybcke Meier", category: "private_person")),
                ("Suppress management person with title", expectHeaderSuppressed(snippet: "Frank Kuhlmann", category: "private_person")),
                ("Keep recipient name", expectContains("Helmut Knobel")),
                ("Keep recipient street", expectContains("Viktor-Scheffel-Str.6")),
                ("Keep recipient postal city", expectContains("74177 Bad Friedrichshall")),
                ("Extract participant slash name", expectRegexMatch(#"(?i)\b(?:Frau|Herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+/[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#, equals: "Herr Knobel/Helmut")),
                ("Extract masked card number", expectRegexMatch(#"(?i)\b(?:Kreditkarten(?:nummer|nr\.?|num(?:mer)?)|Kartennummer|Kartennr\.?|Karten(?:nr\.?|nummer)|Credit\s*Card\s*Number|Card\s*Number|Kreditkarte)[:\s-]+(?:[\d*][\s\-*]?){12,22}[\d*]\b"#, equals: "Kartennr.: 523278****649"))
            ]
        ),
        FixtureCase(
            documentClass: "Telekommunikation / Vertragsbrief",
            fixturePath: "fixtures/detection/telekommunikation_vertragsbrief_native_pdf_text.txt",
            checks: [
                ("Fixture contains Anschlussinhaber label", expectContains("Anschlussinhaber")),
                ("Fixture contains Nutzungsadresse label", expectContains("Nutzungsadresse")),
                ("Suppress sender street", expectSenderSuppressed(snippet: "Hafenstraße 22", category: "private_address")),
                ("Suppress sender postal city", expectSenderSuppressed(snippet: "28195 Weserstadt", category: "private_address")),
                ("Avoid footer postal fragment from Steuer-Nr", expectRegexNoMatch(tightenedGermanPostalCityPattern, forbidden: "09111 Vorsitzender")),
                ("Keep account holder name", expectContains("Mara und Jonas Feld")),
                ("Keep billing street", expectContains("Eichenweg 9")),
                ("Keep billing postal city", expectContains("24568 Hohenfelde")),
                ("Extract Kundennummer", expectRegexMatch(#"(?<=\bKundennummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "NK-2026-44318")),
                ("Extract Vertragsnummer", expectRegexMatch(#"(?<=\bVertragsnummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, equals: "MC-2026-1184"))
            ]
        ),
        FixtureCase(
            documentClass: "Telekommunikation / Rechnung",
            fixturePath: "fixtures/detection/telekom_rechnung_page1_native_pdf_text.txt",
            checks: [
                ("Fixture contains customer data label", expectContains("Telekom Festnetz-Kundendaten")),
                ("Keep recipient name", expectContains("Jonas Weber")),
                ("Keep recipient postal city", expectContains("74229 Sommerfeld")),
                ("Extract spaced Kundennummer without colon", expectRegexMatch(#"(?:(?<=\bKundennummer:\s)|(?<=\bKundennummer\s))(?:[A-Z0-9][A-Z0-9\-]{5,}|\d{2,}(?:\s\d{2,})+)\b"#, equals: "192 002 0638")),
                ("Extract Buchungskonto without colon", expectRegexMatch(#"(?:(?<=\bBuchungskonto:\s)|(?<=\bBuchungskonto\s))(?:\d{2,}(?:\s\d{2,})+|[A-Z0-9][A-Z0-9\- ]{5,})\b"#, equals: "192 002 0638"))
            ]
        )
    ]

    var checksRun = 0
    for fixtureCase in cases {
        let text = try fixture(fixtureCase.fixturePath)
        print("[\(fixtureCase.documentClass)] \(fixtureCase.fixturePath)")
        for (label, check) in fixtureCase.checks {
            do {
                try check(text)
                print("  [OK] \(label)")
                checksRun += 1
            } catch {
                throw DetectionRegressionFailure.failed("[\(fixtureCase.documentClass)] \(label): \(error)")
            }
        }
    }

    return checksRun
}

func runGeneralChecks() throws -> Int {
    try assert(shouldDropModelAccountNumber("001414201"), "Expected short numeric model account number to be dropped")
    try assert(shouldDropModelAccountNumber("95131043000"), "Expected 11-digit model account number to be dropped")
    try assert(!shouldDropModelAccountNumber("5335C01278VC000875401344"), "Expected long alphanumeric account number to remain")

    try assert(
        normalizeOCRText("M a x Mustermann", mode: .ocr) == "MaxMustermann",
        "Expected OCR mode to collapse spaced OCR tokens"
    )
    try assert(
        normalizeOCRText("M a x Mustermann", mode: .native) == "M a x Mustermann",
        "Expected native mode to preserve normal spaced text"
    )
    try assert(
        normalizeOCRText("Gartenstr. 25", mode: .ocr) == "Gartenstr. 25",
        "Expected OCR mode to preserve street name spacing before house numbers"
    )
    try assert(
        looksLikeGermanStreetAddress("Weinbergsteige 2"),
        "Expected street matcher to accept 'Weinbergsteige 2'"
    )
    try assert(
        preservesStrongCustomIdentifier("Jonas Weber"),
        "Expected multi-token custom identifier to remain preservable"
    )

    try assert(
        looksLikeCompanyAddressBlock("Nordlicht Service GmbH Musterweg 88"),
        "Expected company sender block to be recognized as organization address"
    )
    try assert(
        looksLikePostalCity("12345 St. Wendel"),
        "Expected postal city matcher to accept abbreviated city tokens"
    )
    try assert(
        personSpanContainsAddressOrContactTail("Frau Lena Sommer Birkenstraße"),
        "Expected person span with street tail to be rejected"
    )
    try assert(
        personSpanContainsAddressOrContactTail("Frau Nina Weber Lindensteige"),
        "Expected person span with steige-tail to be rejected"
    )
    try assert(
        personSpanContainsAddressOrContactTail("Herr Jonas Sommer E-Mail"),
        "Expected person span with contact-label tail to be rejected"
    )
    try assert(
        looksLikeHonorificStreetCombo("Frau Lena Sommer Birkenstraße 12"),
        "Expected honorific-plus-street combo to be rejected as an overbroad address span"
    )
    try assert(
        looksLikeLeadingConjunctionAddressTail("und Lara Sommer Birkenstr. 12"),
        "Expected conjunction-led address tail to be rejected"
    )
    try assert(
        hasLeadingSentenceFragmentBeforeStreetAddress("ist im Netz. Adolf-Pirrung-Str. 7"),
        "Expected sentence-fragment-plus-street combo to be rejected"
    )
    try assert(
        firstMatch(
            for: #"(?i)\b(?:Kreditkarten(?:nummer|nr\.?|num(?:mer)?)|Kartennummer|Kartennr\.?|Karten(?:nr\.?|nummer)|Credit\s*Card\s*Number|Card\s*Number|Kreditkarte)[:\s-]+(?:[\d*][\s\-*]?){12,22}[\d*]\b"#,
            in: "Kreditkartennummer: 4111 1111 1111 1111"
        ) == "Kreditkartennummer: 4111 1111 1111 1111",
        "Expected labeled credit card number to be extracted"
    )
    try assert(
        firstMatch(
            for: #"(?i)\b(?:Kreditkarten(?:nummer|nr\.?|num(?:mer)?)|Kartennummer|Kartennr\.?|Karten(?:nr\.?|nummer)|Credit\s*Card\s*Number|Card\s*Number|Kreditkarte)[:\s-]+(?:[\d*][\s\-*]?){12,22}[\d*]\b"#,
            in: "Kartennr.: 523278****649"
        ) == "Kartennr.: 523278****649",
        "Expected masked labeled card number to be extracted"
    )
    try assert(
        firstMatch(
            for: #"(?i)\b(?:Frau|Herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+/[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#,
            in: "1. Herr Knobel/Helmut 23.08.1961"
        ) == "Herr Knobel/Helmut",
        "Expected participant slash name to be extracted"
    )
    try assert(
        extractInlineContextPersonName("Bestellt durch: Jonas Weber") == "Jonas Weber",
        "Expected inline 'Bestellt durch' label to expose the customer name"
    )
    try assert(
        extractInlineContextPersonName("Name: Kern Oliver") == "Kern Oliver",
        "Expected generic inline name label to accept reversed order"
    )
    try assert(
        extractInlineContextPersonName("Kontoinhaber: Winter Paula") == "Winter Paula",
        "Expected account-holder label to accept reversed order"
    )
    try assert(
        firstMatch(
            for: #"(?:(?<=\bVorgangsnummer:\s)|(?<=\bVorgangsnummer\s))\d{6,}\b"#,
            in: "Vorgangsnummer 501075621"
        ) == "501075621",
        "Expected Vorgangsnummer without colon to be extracted"
    )
    try assert(
        firstMatch(
            for: #"(?im)(?:(?<=\bMobil:\s)|(?<=\bMobil\s)|(?<=\bHandy:\s)|(?<=\bHandy\s))0\d(?:[\d\s()./\-]{5,}\d)?\b"#,
            in: "Mobil: 0176 12345678"
        ) == "0176 12345678",
        "Expected labeled mobile number to keep its leading zero"
    )
    try assert(
        extractSalutationPersonName("Sehr geehrte Frau Leitz,") == "Frau Leitz",
        "Expected salutation line to expose the honorific surname"
    )
    try assert(
        extractSalutationPersonName("Guten Tag Herr Kern,") == "Herr Kern",
        "Expected Guten-Tag salutation to expose the honorific surname"
    )
    try assert(
        extractSalutationPersonName("Hallo Frau Leitz,") == "Frau Leitz",
        "Expected Hallo salutation to expose the honorific surname"
    )

    return 23
}

func run() throws {
    let generalChecks = try runGeneralChecks()
    let fixtureChecks = try runFixtureCases()
    print("Detection regressions passed (\(generalChecks + fixtureChecks) checks).")
}

do {
    try run()
} catch {
    fputs("Regression failure: \(error)\n", stderr)
    exit(1)
}

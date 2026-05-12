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
        of: #"^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#,
        options: .regularExpression
    ) != nil
    let isBareCityToken = category == "private_person" &&
        cleanedSnippet.range(of: #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]{3,}$"#, options: .regularExpression) != nil
    guard isPostalCity || isBareCityToken else { return false }

    let normalizedSnippet = cleanedSnippet.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let lines = pageText.components(separatedBy: .newlines)
    let headerKeywords = [
        "finanzamt", "finanzkasse", "moltkestr", "moltkestra", "tel", "zi.nr",
        "steuernummer", "idnr", "deutsche post"
    ]

    for (index, line) in lines.enumerated() {
        let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) else { continue }

        let contextStart = max(0, index - 1)
        let contextEnd = min(lines.count - 1, index + 2)
        let context = lines[contextStart...contextEnd]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if headerKeywords.contains(where: { context.contains($0) }) {
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
        of: #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#,
        options: .regularExpression
    ) != nil
}

func looksLikeGermanStreetAddress(_ text: String) -> Bool {
    let cleaned = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.range(
        of: #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer)\s*\d+[A-Za-z]?\b"#,
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
        "strasse", "straße", "str", "weg", "allee", "platz", "gasse", "ring", "ufer"
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
    let recipientMarkers = ["kundin", "kunde", "lieferadresse", "schriftverkehr", "kontoinhaber", "abweichender ansprechpartner"]
    let firstRecipientIndex = lines.firstIndex { line in
        let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return recipientMarkers.contains(where: { folded.contains($0) })
    }

    for (index, line) in lines.enumerated() {
        let normalizedLine = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let compactLine = normalizedComparableText(normalizedLine)
        guard normalizedLine.localizedCaseInsensitiveContains(normalizedSnippet) ||
                (!compactSnippet.isEmpty && compactLine.contains(compactSnippet))
        else { continue }

        let contextStart = max(0, index - 1)
        let contextEnd = min(lines.count - 1, index + 2)
        let context = lines[contextStart...contextEnd]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if let firstRecipientIndex,
           index < firstRecipientIndex,
           senderKeywords.contains(where: { context.contains($0) }) {
            return true
        }
    }

    return false
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

func run() throws {
    let fixtureURL = URL(fileURLWithPath: "fixtures/detection/steuerbescheid_page1_ocr.txt")
    let pageText = try String(contentsOf: fixtureURL, encoding: .utf8)

    try assert(
        shouldSuppressHeaderLikeFinding(snippet: "73084 Falkenstadt", category: "private_address", pageText: pageText),
        "Expected briefkopf postal city '73084 Falkenstadt' to be suppressed"
    )
    try assert(
        shouldSuppressHeaderLikeFinding(snippet: "73086 Falkenstadt", category: "private_address", pageText: pageText),
        "Expected window-address postal city '73086 Falkenstadt' to be suppressed"
    )
    try assert(
        shouldSuppressHeaderLikeFinding(snippet: "Falkenstadt", category: "private_person", pageText: pageText),
        "Expected bare city token 'Falkenstadt' to be suppressed"
    )
    try assert(
        !shouldSuppressHeaderLikeFinding(snippet: "74523 Lindenheim", category: "private_address", pageText: pageText),
        "Expected recipient postal city '74523 Lindenheim' to remain"
    )

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
        normalizeOCRText("Friedenstr. 25", mode: .ocr) == "Friedenstr. 25",
        "Expected OCR mode to preserve street name spacing before house numbers"
    )

    let invoiceFixtureURL = URL(fileURLWithPath: "fixtures/detection/rechnung_senderblock_pdf_text.txt")
    let invoiceText = try String(contentsOf: invoiceFixtureURL, encoding: .utf8)

    try assert(
        looksLikeCompanyAddressBlock("Nordlicht Service GmbH Musterweg 88"),
        "Expected company sender block to be recognized as organization address"
    )
    try assert(
        personSpanContainsAddressOrContactTail("Frau Lena Sommer Birkenstraße"),
        "Expected person span with street tail to be rejected"
    )
    try assert(
        personSpanContainsAddressOrContactTail("Herr Jonas Sommer E-Mail"),
        "Expected person span with contact-label tail to be rejected"
    )
    try assert(
        invoiceText.contains("Abweichender Ansprechpartner:"),
        "Expected invoice sender fixture to contain contact-label context"
    )
    try assert(
        shouldSuppressSenderLikeFinding(snippet: "Musterweg 88", category: "private_address", pageText: invoiceText),
        "Expected sender street to be suppressed in company-header context"
    )
    try assert(
        shouldSuppressSenderLikeFinding(snippet: "Mon<heim", category: "private_person", pageText: invoiceText),
        "Expected sender city token to be suppressed in company-header context"
    )
    try assert(
        looksLikeHonorificStreetCombo("Frau Lena Sommer Birkenstraße 12"),
        "Expected honorific-plus-street combo to be rejected as an overbroad address span"
    )
    try assert(
        firstMatch(
            for: #"(?i)\b\d{5}[ \t]*(?:\n[ \t]*)?(?!(?:Amazon|Bestell|Rechnung|Deutschland|Kontakt|Fax|Geschäftsführer|Registergericht|Kunden|Menge|Lieferung|Lieferadresse)\b)[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}\b(?!<)"#,
            in: invoiceText
        ) != "70173 Stu",
        "Expected postal-city regex not to emit the partial sender city '70173 Stu'"
    )

    let bankFixtureURL = URL(fileURLWithPath: "fixtures/detection/rechnung_bankdaten_page2_pdf_text.txt")
    let bankText = try String(contentsOf: bankFixtureURL, encoding: .utf8)

    try assert(
        firstMatch(for: #"(?<=\bBIC:\s)[A-Z0-9]{8}(?:[A-Z0-9]{3})?\b"#, in: bankText) == "TESTDEFFXXX",
        "Expected BIC regex to extract only the BIC value"
    )
    try assert(
        firstMatch(for: #"(?<=\bKundennummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, in: invoiceText) == "120034854",
        "Expected Kundennummer regex to extract the customer number value"
    )
    try assert(
        firstMatch(for: #"(?<=\bVertragsnummer:\s)[A-Z0-9][A-Z0-9\-]{5,}\b"#, in: invoiceText) == "ES-2026-004281",
        "Expected Vertragsnummer regex to extract the contract number value"
    )
    try assert(
        firstMatch(for: #"(?<=\b(?:Zählernummer|Zaehlernummer):\s)\d{6,}\b"#, in: invoiceText) == "341939022",
        "Expected Zählernummer regex to extract the meter number value"
    )
    try assert(
        firstMatch(for: #"(?<=\bVorgangsnummer:\s)\d{6,}\b"#, in: invoiceText) == "501075621",
        "Expected Vorgangsnummer regex to extract the process number value"
    )

    let contactFixtureURL = URL(fileURLWithPath: "fixtures/detection/kontaktdaten_bankseite_pdf_text.txt")
    let contactText = try String(contentsOf: contactFixtureURL, encoding: .utf8)

    try assert(
        firstMatch(
            for: #"\b[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#,
            in: contactText
        ) == "Milan und Lara Sommer",
        "Expected couple-name regex to extract the full shared-surname name"
    )
    try assert(
        looksLikeLeadingConjunctionAddressTail("und Lara Sommer Birkenstr. 12"),
        "Expected conjunction-led address tail to be rejected"
    )
    try assert(
        firstMatch(for: #"(?<=\bBLZ\s)\d{8}\b"#, in: contactText) == "62050000",
        "Expected BLZ regex to extract the bank code value"
    )
    try assert(
        firstMatch(for: #"(?<=\bKonto\s)\d{5,}\b"#, in: contactText) == "1886182",
        "Expected Konto regex to extract the account number value"
    )

    print("Detection regressions passed.")
}

do {
    try run()
} catch {
    fputs("Regression failure: \(error)\n", stderr)
    exit(1)
}

import Foundation

struct Finding {
    let text: String
    let category: String
    let sourceLabel: String
}

struct PageExpectation {
    let logicalPage: String
    let debugJSON: String
    let title: String
    let mustRedact: [String]
    let mustNotRedact: [String]
    let review: [String]
}

struct PageResult {
    let expectation: PageExpectation
    let jsonPath: String
    let exists: Bool
    let missingMustRedact: [String]
    let leakedMustNotRedact: [(expected: String, finding: Finding)]
    let partialMustRedact: [(expected: String, coverage: Double, findings: [String])]

    var hasFailure: Bool {
        !exists || !missingMustRedact.isEmpty || !leakedMustNotRedact.isEmpty
    }
}

enum ValidatorError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

let arguments = CommandLine.arguments
let expectationPath = arguments.dropFirst().first ?? "fixtures/detection/inkognito_stress_expectations.json"
let exportsDirectory = arguments.dropFirst(2).first ?? "/Users/oliverkern/Downloads"

let expectations = try loadExpectations(at: expectationPath)
let results = try expectations.map { expectation in
    try validate(expectation: expectation, exportsDirectory: exportsDirectory)
}

print("Detection stress expectation check")
print("Expectation: \(expectationPath)")
print("Exports: \(exportsDirectory)")
print("")

var failedPages = 0
var missingJSONs = 0
var missingRedactions = 0
var leakedNonRedactions = 0
var partials = 0

for result in results {
    let status = result.hasFailure ? "FAIL" : "PASS"
    print("[\(status)] \(result.expectation.logicalPage) - \(result.expectation.title)")
    print("  JSON: \(result.jsonPath)")

    if !result.exists {
        print("  Missing export JSON")
        failedPages += 1
        missingJSONs += 1
        continue
    }

    if !result.missingMustRedact.isEmpty {
        print("  Missing must_redact:")
        result.missingMustRedact.forEach { print("    - \($0)") }
        missingRedactions += result.missingMustRedact.count
    }

    if !result.leakedMustNotRedact.isEmpty {
        print("  Unexpected must_not_redact findings:")
        result.leakedMustNotRedact.forEach { item in
            print("    - \(item.expected)  <=  \(item.finding.sourceLabel) \(item.finding.category): \(item.finding.text)")
        }
        leakedNonRedactions += result.leakedMustNotRedact.count
    }

    if !result.partialMustRedact.isEmpty {
        print("  Partial must_redact coverage:")
        result.partialMustRedact.forEach { item in
            let percent = Int((item.coverage * 100).rounded())
            print("    - \(item.expected) (\(percent)% via \(item.findings.joined(separator: " | ")))")
        }
        partials += result.partialMustRedact.count
    }

    if result.expectation.review.isEmpty == false {
        print("  Review notes:")
        result.expectation.review.forEach { print("    - \($0)") }
    }

    if result.hasFailure {
        failedPages += 1
    }
}

print("")
print("Summary:")
print("  Pages: \(results.count)")
print("  Failed pages: \(failedPages)")
print("  Missing JSONs: \(missingJSONs)")
print("  Missing must_redact: \(missingRedactions)")
print("  Unexpected must_not_redact: \(leakedNonRedactions)")
print("  Partial coverage notes: \(partials)")

if failedPages > 0 {
    exit(1)
}

func validate(expectation: PageExpectation, exportsDirectory: String) throws -> PageResult {
    let jsonPath = URL(fileURLWithPath: exportsDirectory)
        .appendingPathComponent(expectation.debugJSON)
        .path
    guard FileManager.default.fileExists(atPath: jsonPath) else {
        return PageResult(
            expectation: expectation,
            jsonPath: jsonPath,
            exists: false,
            missingMustRedact: [],
            leakedMustNotRedact: [],
            partialMustRedact: []
        )
    }

    let page = try loadPageExport(at: jsonPath)
    let findings = page.findings
    let normalizedFindings = findings.map { finding in
        (finding: finding, normalized: normalizedComparableText(finding.text))
    }

    var missingMustRedact: [String] = []
    var partialMustRedact: [(expected: String, coverage: Double, findings: [String])] = []
    for expected in expectation.mustRedact {
        let normalizedExpected = normalizedComparableText(expected)
        guard !normalizedExpected.isEmpty else { continue }

        if normalizedFindings.contains(where: { item in
            isCovered(expected: expected, normalizedExpected: normalizedExpected, by: item.finding, normalizedFinding: item.normalized)
        }) {
            continue
        }

        let coverage = tokenCoverage(for: expected, findings: findings)
        if coverage.ratio >= 0.75 {
            continue
        }
        if coverage.ratio >= 0.5 {
            partialMustRedact.append((expected, coverage.ratio, coverage.matchedFindings))
        }
        missingMustRedact.append(expected)
    }

    var leakedMustNotRedact: [(expected: String, finding: Finding)] = []
    for expected in expectation.mustNotRedact {
        let normalizedExpected = normalizedComparableText(expected)
        guard !normalizedExpected.isEmpty else { continue }
        for item in normalizedFindings where isForbiddenFinding(expected: expected, normalizedExpected: normalizedExpected, finding: item.finding, normalizedFinding: item.normalized) {
            leakedMustNotRedact.append((expected, item.finding))
        }
    }

    return PageResult(
        expectation: expectation,
        jsonPath: jsonPath,
        exists: true,
        missingMustRedact: missingMustRedact,
        leakedMustNotRedact: leakedMustNotRedact,
        partialMustRedact: partialMustRedact
    )
}

func isCovered(
    expected: String,
    normalizedExpected: String,
    by finding: Finding,
    normalizedFinding: String
) -> Bool {
    guard !normalizedFinding.isEmpty else { return false }
    if normalizedFinding.contains(normalizedExpected) {
        return true
    }

    let strippedPrefixes = ["fuer ", "für "]
    for prefix in strippedPrefixes where expected.lowercased().hasPrefix(prefix) {
        let remainder = String(expected.dropFirst(prefix.count))
        let normalizedRemainder = normalizedComparableText(remainder)
        if !normalizedRemainder.isEmpty, normalizedFinding.contains(normalizedRemainder) {
            return true
        }
    }

    return normalizedExpected.count >= 8 && normalizedExpected.contains(normalizedFinding)
}

func isForbiddenFinding(
    expected: String,
    normalizedExpected: String,
    finding: Finding,
    normalizedFinding: String
) -> Bool {
    guard !normalizedFinding.isEmpty else { return false }
    let labelLike = expected.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":")
    if labelLike {
        return normalizedFinding == normalizedExpected
    }
    return normalizedFinding.contains(normalizedExpected)
}

func loadExpectations(at path: String) throws -> [PageExpectation] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let pages = root["pages"] as? [[String: Any]]
    else {
        throw ValidatorError.message("Could not read pages from \(path)")
    }

    return pages.map { page in
        PageExpectation(
            logicalPage: page["logical_page"] as? String ?? "<unknown>",
            debugJSON: page["debug_json"] as? String ?? "",
            title: page["title"] as? String ?? "",
            mustRedact: page["must_redact"] as? [String] ?? [],
            mustNotRedact: page["must_not_redact"] as? [String] ?? [],
            review: page["review"] as? [String] ?? []
        )
    }
}

func loadPageExport(at path: String) throws -> (findings: [Finding], rawText: String, normalizedText: String) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ValidatorError.message("Could not read page export at \(path)")
    }

    let findingDictionaries = root["findings"] as? [[String: Any]] ?? []
    let findings = findingDictionaries.map { finding in
        Finding(
            text: finding["text"] as? String ?? "",
            category: finding["category"] as? String ?? "",
            sourceLabel: finding["sourceLabel"] as? String ?? ""
        )
    }

    return (
        findings,
        root["rawText"] as? String ?? "",
        root["normalizedText"] as? String ?? ""
    )
}

func tokenCoverage(for expected: String, findings: [Finding]) -> (ratio: Double, matchedFindings: [String]) {
    let expectedTokens = Set(tokens(in: expected))
    guard !expectedTokens.isEmpty else { return (1, []) }

    var matchedTokens = Set<String>()
    var matchedFindings: [String] = []
    for finding in findings {
        if finding.category == "private_email", !expected.contains("@") {
            continue
        }
        let findingTokens = Set(tokens(in: finding.text))
        let overlap = expectedTokens.intersection(findingTokens)
        if !overlap.isEmpty {
            matchedTokens.formUnion(overlap)
            matchedFindings.append(finding.text)
        }
    }

    return (Double(matchedTokens.count) / Double(expectedTokens.count), matchedFindings)
}

func tokens(in text: String) -> [String] {
    normalizedWords(text)
        .filter { token in
            token.count > 1 || token.rangeOfCharacter(from: .decimalDigits) != nil
        }
}

func normalizedWords(_ text: String) -> [String] {
    normalize(text)
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

func normalizedComparableText(_ text: String) -> String {
    normalize(text)
        .filter { character in
            character.isLetter || character.isNumber
        }
}

func normalize(_ text: String) -> String {
    text
        .replacingOccurrences(of: "ß", with: "ss")
        .replacingOccurrences(of: "ẞ", with: "ss")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        .lowercased()
}

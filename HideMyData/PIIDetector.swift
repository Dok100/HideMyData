import Foundation
import CoreGraphics
@preconcurrency import OpenMedKit

enum DetectionSource: String, Codable, Sendable {
    case model
    case pattern
    case mixed

    var label: String {
        switch self {
        case .model: "Modell"
        case .pattern: "Regex"
        case .mixed: "Modell + Regex"
        }
    }
}

enum ReviewStatus: String, Codable, Sendable {
    case pending
    case accepted
    case rejected

    var label: String {
        switch self {
        case .pending: "Offen"
        case .accepted: "Bestätigt"
        case .rejected: "Abgelehnt"
        }
    }
}

struct ReviewFinding: Identifiable, Equatable, Sendable {
    let id: UUID
    let category: String
    let snippet: String
    let source: DetectionSource
    let confidence: Float
    let pageIndex: Int?
    var status: ReviewStatus

    init(
        id: UUID = UUID(),
        category: String,
        snippet: String,
        source: DetectionSource,
        confidence: Float,
        pageIndex: Int? = nil,
        status: ReviewStatus = .pending
    ) {
        self.id = id
        self.category = category
        self.snippet = snippet
        self.source = source
        self.confidence = confidence
        self.pageIndex = pageIndex
        self.status = status
    }
}

struct ReviewFindingCandidate {
    let category: String
    let snippet: String
    let source: DetectionSource
    let confidence: Float
    let pageIndex: Int?
    let rects: [CGRect]
}

struct ReviewFindingProjection {
    let finding: ReviewFinding
    let rects: [CGRect]
}

enum ReviewFindingCompactor {
    private enum Family: String {
        case addressBlock
        case contact
        case standalone
    }

    private struct Cluster {
        var candidates: [ReviewFindingCandidate]
        let family: Family
        let pageIndex: Int?

        var unionRect: CGRect {
            candidates
                .flatMap(\.rects)
                .reduce(.null) { partial, rect in
                    partial.isNull ? rect : partial.union(rect)
                }
        }
    }

    static func compact(_ candidates: [ReviewFindingCandidate]) -> [ReviewFindingProjection] {
        let filtered = suppressRedundantCandidates(candidates)
        let clustered = cluster(filtered)
        return clustered.map(makeProjection)
    }

    private static func suppressRedundantCandidates(_ candidates: [ReviewFindingCandidate]) -> [ReviewFindingCandidate] {
        candidates.filter { candidate in
            let normalizedCandidate = normalized(candidate.snippet)
            guard !normalizedCandidate.isEmpty else { return false }

            if candidate.category == "private_address",
               looksLikeGermanPostalCity(candidate.snippet),
               isRepeatedNonRecipientPostalCity(candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_address",
               looksLikeGermanPostalCity(candidate.snippet),
               hasNearbyAuthorityContext(for: candidate, in: candidates) &&
               !hasNearbyRecipientContext(for: candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_address",
               (looksLikeGermanPostalCity(candidate.snippet) || looksLikeGermanStreetAddress(candidate.snippet)),
               hasNearbySenderContext(for: candidate, in: candidates) &&
               !hasNearbyRecipientContext(for: candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_person",
               looksLikeBareCityToken(candidate.snippet),
               matchesRepeatedNonRecipientPostalCity(candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_person",
               looksLikeBareCityToken(candidate.snippet),
               hasNearbyAuthorityContext(for: candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_person",
               looksLikeBareCityToken(candidate.snippet),
               hasNearbySenderContext(for: candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_address",
               looksLikeCompanyAddressBlock(candidate.snippet) {
                return false
            }

            if candidate.category == "private_address",
               addressLikelyContainsPersonTail(candidate.snippet),
               candidates.contains(where: { other in
                   guard !areSameCandidate(candidate, other),
                         other.category == "private_address",
                         other.pageIndex == candidate.pageIndex,
                         looksLikeGermanPostalCity(other.snippet)
                   else { return false }
                   return rectGroupsOverlap(candidate.rects, other.rects)
               }) {
                return false
            }

            return !candidates.contains { other in
                guard !areSameCandidate(candidate, other),
                      candidate.pageIndex == other.pageIndex
                else { return false }

                let normalizedOther = normalized(other.snippet)
                guard !normalizedOther.isEmpty,
                      normalizedOther.count > normalizedCandidate.count,
                      normalizedOther.contains(normalizedCandidate)
                else { return false }

                if candidate.category == "private_address",
                   other.category == "private_address",
                   looksLikeGermanPostalCity(candidate.snippet),
                   addressLikelyContainsPersonTail(other.snippet) {
                    return false
                }

                if family(for: candidate.category) == .standalone,
                   family(for: other.category) == .standalone,
                   candidate.category != other.category {
                    return false
                }

                return rectGroupsOverlap(candidate.rects, other.rects)
            }
        }
    }

    private static func cluster(_ candidates: [ReviewFindingCandidate]) -> [Cluster] {
        var clusters: [Cluster] = []

        for candidate in candidates {
            let candidateFamily = family(for: candidate.category)
            if let index = clusters.firstIndex(where: { shouldGroup(candidate, with: $0, family: candidateFamily) }) {
                clusters[index].candidates.append(candidate)
            } else {
                clusters.append(
                    Cluster(
                        candidates: [candidate],
                        family: candidateFamily,
                        pageIndex: candidate.pageIndex
                    )
                )
            }
        }

        return clusters
    }

    private static func shouldGroup(_ candidate: ReviewFindingCandidate, with cluster: Cluster, family: Family) -> Bool {
        guard cluster.pageIndex == candidate.pageIndex,
              cluster.family == family,
              family != .standalone
        else {
            return false
        }

        if family == .contact {
            return true
        }

        let candidateBounds = union(of: candidate.rects)
        guard !candidateBounds.isNull else { return false }

        let expanded = cluster.unionRect.insetBy(dx: -18, dy: -26)
        if expanded.intersects(candidateBounds) {
            return true
        }

        let verticalGap = gapBetween(cluster.unionRect.minY...cluster.unionRect.maxY, candidateBounds.minY...candidateBounds.maxY)
        let horizontalGap = gapBetween(cluster.unionRect.minX...cluster.unionRect.maxX, candidateBounds.minX...candidateBounds.maxX)
        return verticalGap <= 20 && horizontalGap <= 80
    }

    private static func makeProjection(from cluster: Cluster) -> ReviewFindingProjection {
        let sortedCandidates = cluster.candidates.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.snippet.count > rhs.snippet.count
            }
            return lhs.confidence > rhs.confidence
        }

        let source = mergedSource(sortedCandidates.map(\.source))
        let confidence = sortedCandidates.map(\.confidence).max() ?? 0
        let pageIndex = cluster.pageIndex
        let category = summarizedCategory(for: cluster)
        let snippet = summarizedSnippet(for: cluster)
        let finding = ReviewFinding(
            category: category,
            snippet: snippet,
            source: source,
            confidence: confidence,
            pageIndex: pageIndex
        )

        return ReviewFindingProjection(
            finding: finding,
            rects: cluster.candidates.flatMap(\.rects)
        )
    }

    private static func summarizedCategory(for cluster: Cluster) -> String {
        switch cluster.family {
        case .addressBlock:
            let categories = Set(cluster.candidates.map(\.category))
            if categories.contains("private_person") && categories.contains("private_address") {
                return "Adressblock"
            }
            return "Adresse"
        case .contact:
            let categories = Set(cluster.candidates.map(\.category))
            if categories.count > 1 {
                return "Kontakt"
            }
            return cluster.candidates.first?.category ?? "Kontakt"
        case .standalone:
            return cluster.candidates.first?.category ?? "Treffer"
        }
    }

    private static func summarizedSnippet(for cluster: Cluster) -> String {
        var snippets: [String] = []
        var seen = Set<String>()

        let orderedCandidates = cluster.candidates.sorted { lhs, rhs in
            let lhsBounds = union(of: lhs.rects)
            let rhsBounds = union(of: rhs.rects)
            if abs(lhsBounds.minY - rhsBounds.minY) > 8 {
                return lhsBounds.minY > rhsBounds.minY
            }
            if abs(lhsBounds.minX - rhsBounds.minX) > 8 {
                return lhsBounds.minX < rhsBounds.minX
            }
            return lhs.snippet.count > rhs.snippet.count
        }

        for candidate in orderedCandidates {
            let cleaned = candidate.snippet
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = normalized(cleaned)
            guard seen.insert(key).inserted else { continue }
            snippets.append(cleaned)
        }

        switch cluster.family {
        case .addressBlock:
            return snippets.prefix(4).joined(separator: "\n")
        case .contact:
            return snippets.prefix(4).joined(separator: "\n")
        case .standalone:
            return snippets.first ?? ""
        }
    }

    private static func family(for category: String) -> Family {
        switch category {
        case "private_person", "private_address", "custom_identifier":
            return .addressBlock
        case "private_phone", "private_email":
            return .contact
        default:
            return .standalone
        }
    }

    private static func mergedSource(_ sources: [DetectionSource]) -> DetectionSource {
        let unique = Set(sources)
        if unique.count > 1 || unique.contains(.mixed) {
            return .mixed
        }
        return sources.first ?? .pattern
    }

    private static func union(of rects: [CGRect]) -> CGRect {
        rects.reduce(.null) { partial, rect in
            partial.isNull ? rect : partial.union(rect)
        }
    }

    private static func rectGroupsOverlap(_ lhs: [CGRect], _ rhs: [CGRect]) -> Bool {
        let lhsUnion = union(of: lhs)
        let rhsUnion = union(of: rhs)
        guard !lhsUnion.isNull, !rhsUnion.isNull else { return false }
        return lhsUnion.insetBy(dx: -10, dy: -10).intersects(rhsUnion)
    }

    private static func gapBetween(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        if lhs.overlaps(rhs) { return 0 }
        if lhs.upperBound < rhs.lowerBound { return rhs.lowerBound - lhs.upperBound }
        return lhs.lowerBound - rhs.upperBound
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    private static func looksLikeGermanPostalCity(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeGermanStreetAddress(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeGermanPostalCity(cleaned) || looksLikeGermanStreetAddress(cleaned) {
            return true
        }
        let pattern = #"(?i)\b(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+.+\d{5}\s+[A-ZÄÖÜa-zäöüß]"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func addressLikelyContainsPersonTail(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß]+){2,}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func hasNearbyRecipientContext(for candidate: ReviewFindingCandidate, in candidates: [ReviewFindingCandidate]) -> Bool {
        let candidateBounds = union(of: candidate.rects)
        guard !candidateBounds.isNull else { return false }

        return candidates.contains { other in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex
            else { return false }

            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return false }

            let otherLooksRecipientLike =
                other.category == "private_person" ||
                (other.category == "private_address" &&
                 (looksLikeGermanStreetAddress(other.snippet) ||
                  looksLikeAddressBlock(other.snippet) ||
                  addressLikelyContainsPersonTail(other.snippet)))
            guard otherLooksRecipientLike else { return false }

            if candidateBounds.insetBy(dx: -24, dy: -28).intersects(otherBounds) {
                return true
            }

            let verticalGap = gapBetween(candidateBounds.minY...candidateBounds.maxY, otherBounds.minY...otherBounds.maxY)
            let horizontalGap = gapBetween(candidateBounds.minX...candidateBounds.maxX, otherBounds.minX...otherBounds.maxX)
            return verticalGap <= 44 && horizontalGap <= 160
        }
    }

    private static func isRepeatedNonRecipientPostalCity(_ candidate: ReviewFindingCandidate, in candidates: [ReviewFindingCandidate]) -> Bool {
        guard let city = postalCityName(from: candidate.snippet),
              !hasNearbyRecipientContext(for: candidate, in: candidates)
        else { return false }

        return candidates.contains { other in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex,
                  looksLikeGermanPostalCity(other.snippet),
                  !hasNearbyRecipientContext(for: other, in: candidates),
                  let otherCity = postalCityName(from: other.snippet)
            else { return false }
            return otherCity == city
        }
    }

    private static func matchesRepeatedNonRecipientPostalCity(_ candidate: ReviewFindingCandidate, in candidates: [ReviewFindingCandidate]) -> Bool {
        let normalizedCandidate = normalized(candidate.snippet)
        guard !normalizedCandidate.isEmpty else { return false }

        return candidates.contains { other in
            guard other.pageIndex == candidate.pageIndex,
                  looksLikeGermanPostalCity(other.snippet),
                  isRepeatedNonRecipientPostalCity(other, in: candidates),
                  let otherCity = postalCityName(from: other.snippet)
            else { return false }
            return normalized(otherCity) == normalizedCandidate
        }
    }

    private static func hasNearbyAuthorityContext(for candidate: ReviewFindingCandidate, in candidates: [ReviewFindingCandidate]) -> Bool {
        let candidateBounds = union(of: candidate.rects)
        guard !candidateBounds.isNull else { return false }

        let recipientCenters = candidates.compactMap { other -> CGFloat? in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex
            else { return nil }
            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return nil }

            let otherLooksRecipientLike =
                other.category == "private_person" ||
                (other.category == "private_address" &&
                 (looksLikeGermanStreetAddress(other.snippet) ||
                  looksLikeAddressBlock(other.snippet) ||
                  addressLikelyContainsPersonTail(other.snippet)))
            guard otherLooksRecipientLike else { return nil }
            return otherBounds.midY
        }

        let authorityOnPage = candidates.contains { other in
            other.pageIndex == candidate.pageIndex && looksLikeAuthoritySnippet(other.snippet)
        }
        if authorityOnPage,
           let recipientBandTop = recipientCenters.max(),
           candidateBounds.midY + 120 < recipientBandTop {
            return true
        }

        return candidates.contains { other in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex,
                  looksLikeAuthoritySnippet(other.snippet)
            else { return false }

            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return false }

            if candidateBounds.insetBy(dx: -28, dy: -30).intersects(otherBounds) {
                return true
            }

            let verticalGap = gapBetween(candidateBounds.minY...candidateBounds.maxY, otherBounds.minY...otherBounds.maxY)
            let horizontalGap = gapBetween(candidateBounds.minX...candidateBounds.maxX, otherBounds.minX...otherBounds.maxX)
            return verticalGap <= 36 && horizontalGap <= 220
        }
    }

    private static func hasNearbySenderContext(for candidate: ReviewFindingCandidate, in candidates: [ReviewFindingCandidate]) -> Bool {
        let candidateBounds = union(of: candidate.rects)
        guard !candidateBounds.isNull else { return false }

        let recipientCenters = candidates.compactMap { other -> CGFloat? in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex
            else { return nil }
            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return nil }

            let otherLooksRecipientLike =
                other.category == "private_person" ||
                (other.category == "private_address" &&
                 (looksLikeGermanStreetAddress(other.snippet) ||
                  looksLikeAddressBlock(other.snippet) ||
                  addressLikelyContainsPersonTail(other.snippet)))
            guard otherLooksRecipientLike else { return nil }
            return otherBounds.midY
        }

        let senderOnPage = candidates.contains { other in
            other.pageIndex == candidate.pageIndex && looksLikeOrganizationSnippet(other.snippet)
        }
        if senderOnPage,
           let recipientBandTop = recipientCenters.max(),
           candidateBounds.midY + 120 < recipientBandTop {
            return true
        }

        return candidates.contains { other in
            guard !areSameCandidate(candidate, other),
                  other.pageIndex == candidate.pageIndex,
                  looksLikeOrganizationSnippet(other.snippet)
            else { return false }

            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return false }

            if candidateBounds.insetBy(dx: -28, dy: -30).intersects(otherBounds) {
                return true
            }

            let verticalGap = gapBetween(candidateBounds.minY...candidateBounds.maxY, otherBounds.minY...otherBounds.maxY)
            let horizontalGap = gapBetween(candidateBounds.minX...candidateBounds.maxX, otherBounds.minX...otherBounds.maxX)
            return verticalGap <= 42 && horizontalGap <= 240
        }
    }

    private static func looksLikeAuthoritySnippet(_ text: String) -> Bool {
        let normalizedText = normalized(text)
        return normalizedText.contains("finanzamt") ||
            normalizedText.contains("finanzkasse") ||
            normalizedText.contains("steuernummer") ||
            normalizedText.contains("idnr")
    }

    private static func looksLikeOrganizationSnippet(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeCompanyAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeOrganizationSnippet(cleaned) else { return false }
        return looksLikeGermanStreetAddress(cleaned) ||
            looksLikeGermanPostalCity(cleaned) ||
            cleaned.range(of: #"\b\d+[A-Za-z]?\b"#, options: .regularExpression) != nil
    }

    private static func looksLikeBareCityToken(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]{3,}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func postalCityName(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = cleaned.range(of: #"^(?:D\s*-\s*)?\d{5}\s+(.+)$"#, options: .regularExpression) else {
            return nil
        }
        let suffix = String(cleaned[range]).replacingOccurrences(
            of: #"^(?:D\s*-\s*)?\d{5}\s+"#,
            with: "",
            options: .regularExpression
        )
        let normalizedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedSuffix.isEmpty ? nil : normalizedSuffix
    }

    private static func areSameCandidate(_ lhs: ReviewFindingCandidate, _ rhs: ReviewFindingCandidate) -> Bool {
        lhs.category == rhs.category &&
        lhs.snippet == rhs.snippet &&
        lhs.pageIndex == rhs.pageIndex &&
        lhs.source == rhs.source &&
        lhs.rects == rhs.rects
    }
}

struct DetectedSpan: Identifiable, Equatable, Sendable {
    let id = UUID()
    let category: String
    let text: String
    let start: Int
    let end: Int
    let confidence: Float
    let source: DetectionSource
}

struct DetectionDebugEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let textSourceLabel: String
    let rawText: String
    let normalizedText: String
    let findings: [DetectedSpan]
}

struct TextAnonymizationResult: Sendable {
    let anonymizedText: String
    let replacementCount: Int
    let placeholders: [String: String]
}

struct ClipboardAnonymizationSession: Codable, Sendable {
    let originalText: String
    let anonymizedText: String
    let replacementCount: Int
    let placeholders: [String: String]
    let createdAt: Date
}

struct TextRestorationResult: Sendable {
    let restoredText: String
    let replacementCount: Int
    let unresolvedPlaceholders: [String]
    let suspiciousTokens: [String]
}

@Observable
@MainActor
final class PIIDetector {
    enum Phase: Equatable {
        case needsDownload
        case downloading(downloaded: Int64, total: Int64)
        case loadingModel
        case warmingUp
        case ready
        case running
        case failed(String)
    }

    var phase: Phase
    var lastClipboardSession: ClipboardAnonymizationSession?

    private var openmed: OpenMed?
    private static let lastClipboardSessionKey = "Inkognito.lastClipboardSession"
    private static let legacyLastClipboardSessionKey = "HMD.lastClipboardSession"

    static let modelRepoID = "OpenMed/privacy-filter-mlx-8bit"
    static let modelRevision = "4c9836d"
    static let modelURL = URL(string: "https://huggingface.co/\(modelRepoID)/tree/\(modelRevision)")!

    private static func defaultCacheRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateLegacyCacheIfNeeded(base: support)
        return support
            .appendingPathComponent("Inkognito", isDirectory: true)
            .appendingPathComponent("ModelCache", isDirectory: true)
    }

    private static func migrateLegacyCacheIfNeeded(base: URL) {
        let fm = FileManager.default
        let legacyDir = base.appendingPathComponent("HideMyData/ModelCache", isDirectory: true)
        let newParent = base.appendingPathComponent("Inkognito", isDirectory: true)
        let newDir = newParent.appendingPathComponent("ModelCache", isDirectory: true)

        guard fm.fileExists(atPath: legacyDir.path),
              !fm.fileExists(atPath: newDir.path) else { return }

        try? fm.createDirectory(at: newParent, withIntermediateDirectories: true)
        try? fm.moveItem(at: legacyDir, to: newDir)
    }

    private static func modelDirectory(in cacheRoot: URL) -> URL {
        cacheRoot
            .appendingPathComponent(Self.modelRepoID.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
            .appendingPathComponent(Self.modelRevision, isDirectory: true)
    }

    private static func readyMarkerURL(in cacheRoot: URL) -> URL {
        modelDirectory(in: cacheRoot).appendingPathComponent(".openmed-artifact-ready")
    }

    private var cacheRoot: URL { Self.defaultCacheRoot() }
    private var modelDirectory: URL {
        Self.modelDirectory(in: cacheRoot)
    }
    private var readyMarkerURL: URL {
        Self.readyMarkerURL(in: cacheRoot)
    }

    init() {
        let cacheRoot = Self.defaultCacheRoot()
        let hasReadyMarker = FileManager.default.fileExists(atPath: Self.readyMarkerURL(in: cacheRoot).path)
        self.phase = hasReadyMarker ? .loadingModel : .needsDownload
        self.lastClipboardSession = Self.loadPersistedClipboardSession()
    }

    var statusText: String {
        switch phase {
        case .needsDownload: "Modell nicht heruntergeladen"
        case .downloading(let downloaded, let total): Self.downloadStatus(downloaded: downloaded, total: total)
        case .loadingModel: "Modell wird geladen…"
        case .warmingUp: "Modell wird vorbereitet…"
        case .ready: "Bereit"
        case .running: "Wird ausgeführt…"
        case .failed(let message): "Fehler: \(message)"
        }
    }

    private static func downloadStatus(downloaded: Int64, total: Int64) -> String {
        let downloadedStr = downloaded.formatted(.byteCount(style: .file))
        guard total > 0 else { return "Wird heruntergeladen… bisher \(downloadedStr)" }
        let totalStr = total.formatted(.byteCount(style: .file))
        let pct = (Double(downloaded) / Double(total))
            .formatted(.percent.precision(.fractionLength(0)))
        return "Wird heruntergeladen… \(downloadedStr) / \(totalStr) (\(pct))"
    }

    var isReady: Bool {
        switch phase {
        case .ready, .running: true
        default: false
        }
    }

    var isBusy: Bool {
        switch phase {
        case .loadingModel, .warmingUp, .running, .downloading: return true
        default: return false
        }
    }

    // MARK: - Lifecycle

    func loadIfCached() async {
        ensureCacheDirectoryExists()
        if case .loadingModel = phase {
            await loadCachedModel()
        }
    }

    func startDownload() async {
        ensureCacheDirectoryExists()
        phase = .downloading(downloaded: 0, total: 0)

        let downloader = ModelDownloader(
            repoID: Self.modelRepoID,
            revision: Self.modelRevision,
            cacheRoot: cacheRoot
        )
        downloader.onProgress = { [weak self] downloaded, total in
            guard let self else { return }
            self.phase = .downloading(downloaded: downloaded, total: total)
        }

        do {
            _ = try await downloader.download()
            await loadCachedModel()
        } catch {
            phase = .failed("Download fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func loadCachedModel() async {
        phase = .loadingModel
        do {
            guard FileManager.default.fileExists(atPath: readyMarkerURL.path) else {
                phase = .needsDownload
                return
            }
            openmed = try OpenMed(backend: .mlx(modelDirectoryURL: modelDirectory))
            await warmUp()
        } catch {
            phase = .failed("Laden fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func warmUp() async {
        phase = .warmingUp
        let model = openmed
        _ = await runOnBackground { try? model?.extractPII("Aufwärmen.", confidenceThreshold: 0.5, useSmartMerging: false) }
        phase = .ready
    }

    // MARK: - Inference

    func detect(_ text: String) async -> Result<[DetectedSpan], Error> {
        guard let model = openmed else {
            return .failure(HMDError.message("Erkennung ist nicht geladen"))
        }
        let prevPhase = phase
        phase = .running
        defer { phase = prevPhase }

        return await runOnBackground {
            do {
                let entities = try model.extractPII(text, confidenceThreshold: 0.4, useSmartMerging: false)
                let modelSpans = entities.map {
                    DetectedSpan(
                        category: $0.label,
                        text: $0.text,
                        start: $0.start,
                        end: $0.end,
                        confidence: $0.confidence,
                        source: .model
                    )
                }
                let patternSpans = PatternMatcher.detect(text)
                return .success(Self.postProcessSpans(modelSpans + patternSpans))
            } catch {
                return .failure(error)
            }
        }
    }

    func anonymizeText(_ text: String) async -> Result<TextAnonymizationResult, Error> {
        switch await detect(text) {
        case .failure(let error):
            return .failure(error)
        case .success(let spans):
            return .success(Self.placeholderize(text: text, spans: spans))
        }
    }

    func anonymizeClipboardText(_ text: String) async -> Result<ClipboardAnonymizationSession, Error> {
        switch await anonymizeText(text) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            let session = ClipboardAnonymizationSession(
                originalText: text,
                anonymizedText: result.anonymizedText,
                replacementCount: result.replacementCount,
                placeholders: result.placeholders,
                createdAt: Date()
            )
            lastClipboardSession = session
            Self.persistClipboardSession(session)
            return .success(session)
        }
    }

    func restoreText(_ text: String) -> TextRestorationResult? {
        guard let session = lastClipboardSession else { return nil }
        return Self.restorePlaceholders(in: text, placeholders: session.placeholders)
    }

    // MARK: - Helpers

    private func runOnBackground<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    nonisolated private static func postProcessSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        let sanitized = sanitizeSpans(spans)
        let deduplicated = deduplicateExactSpans(sanitized)
        let merged = mergeEquivalentSpans(deduplicated)
        return suppressContainedCustomIdentifierSpans(merged)
    }

    nonisolated private static func sanitizeSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.compactMap { span in
            let cleanedText = cleanedSpanText(span.text)
            guard !shouldDropSpan(category: span.category, text: cleanedText, source: span.source) else {
                return nil
            }
            let category = sanitizedCategory(for: span.category, text: cleanedText)
            return DetectedSpan(
                category: category,
                text: cleanedText,
                start: span.start,
                end: span.end,
                confidence: span.confidence,
                source: span.source
            )
        }
    }

    nonisolated private static func cleanedSpanText(_ text: String) -> String {
        OCRNormalizer.normalize(text, mode: .native).text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func sanitizedCategory(for category: String, text: String) -> String {
        guard category == "account_number" else { return category }
        return looksLikePostalCity(text) ? "private_address" : category
    }

    nonisolated private static func shouldDropSpan(category: String, text: String, source: DetectionSource) -> Bool {
        guard !text.isEmpty else { return true }

        switch category {
        case "private_person":
            if isDocumentNoise(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            if looksLikeOrganizationSnippet(text) || personSpanContainsAddressOrContactTail(text) {
                return true
            }
            if source == .model, text.count <= 4, !looksLikeNameishWord(text) {
                return true
            }
            if source == .model, text.rangeOfCharacter(from: .decimalDigits) != nil, !text.contains(" ") {
                return true
            }
            return false

        case "private_address":
            if isDocumentNoise(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            if looksLikeCompanyAddressBlock(text) {
                return true
            }
            if looksLikeHonorificStreetCombo(text) {
                return true
            }
            if looksLikePostalCity(text) || looksLikeGermanStreetAddress(text) || looksLikeAddressBlock(text) {
                return false
            }
            if source == .pattern {
                return true
            }
            return text.count < 8

        case "account_number":
            if source != .model {
                return false
            }
            if looksLikePostalCity(text) || looksLikeGermanStreetAddress(text) || looksLikeTaxOfficeHeader(text) {
                return true
            }
            let digitsOnly = text.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
            let hasLetters = text.rangeOfCharacter(from: .letters) != nil
            if !hasLetters && digitsOnly.count < 12 {
                return true
            }
            return false

        default:
            return false
        }
    }

    nonisolated private static func looksLikePostalCity(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß]+(?:[ -][A-Za-zÄÖÜäöüß]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeGermanStreetAddress(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse|weg|allee|platz|gasse|ring|ufer)\s*\d+[A-Za-z]?\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikePostalCity(cleaned) || looksLikeGermanStreetAddress(cleaned) {
            return true
        }
        let pattern = #"(?i)\b(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+.+\d{5}\s+[A-ZÄÖÜa-zäöüß]"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeCompanyAddressBlock(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeOrganizationSnippet(cleaned) else { return false }
        return looksLikeGermanStreetAddress(cleaned) ||
            looksLikePostalCity(cleaned) ||
            cleaned.range(of: #"\b\d+[A-Za-z]?\b"#, options: .regularExpression) != nil
    }

    nonisolated private static func personSpanContainsAddressOrContactTail(_ text: String) -> Bool {
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

    nonisolated private static func looksLikeHonorificStreetCombo(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikePostalCity(cleaned),
              looksLikeGermanStreetAddress(cleaned)
        else { return false }

        let pattern = #"(?i)^(?:frau|herr)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeNameishWord(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3, cleaned.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let pattern = #"^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeTaxOfficeHeader(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        return normalizedText.contains("finanzamt") ||
            normalizedText.contains("finanzkasse") ||
            normalizedText.contains("steuernummer") ||
            normalizedText.contains("idnr") ||
            normalizedText.contains("bescheid")
    }

    nonisolated private static func looksLikeOrganizationSnippet(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:gmbh|mbh|ag|ug|kg|ohg|gbr|llc|ltd|inc)\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func isDocumentNoise(_ text: String) -> Bool {
        let normalizedText = normalizedComparableText(text)
        let bannedFragments = [
            "eink", "einkommensteuer", "kirchensteuer", "solidaritatszuschlag",
            "fortsotzung", "fortsetzung", "nachsteseite", "nachsteselte",
            "selto", "luszetch", "reste", "ruckfragen", "angeben"
        ]
        return bannedFragments.contains { normalizedText.contains($0) }
    }

    nonisolated private static func deduplicateExactSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var bestByKey: [String: DetectedSpan] = [:]
        var order: [String] = []

        for span in spans {
            let key = exactSpanKey(span)
            if let existing = bestByKey[key] {
                if span.confidence > existing.confidence {
                    bestByKey[key] = span
                }
            } else {
                bestByKey[key] = span
                order.append(key)
            }
        }

        return order.compactMap { bestByKey[$0] }
    }

    nonisolated private static func suppressContainedCustomIdentifierSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        spans.filter { candidate in
            guard candidate.category == "custom_identifier" else {
                return true
            }

            let candidateLength = candidate.end - candidate.start
            return !spans.contains { other in
                guard other.id != candidate.id,
                      other.end > other.start
                else { return false }

                let otherLength = other.end - other.start
                guard otherLength > candidateLength else { return false }

                if other.start <= candidate.start && other.end >= candidate.end {
                    return true
                }

                let overlapStart = max(candidate.start, other.start)
                let overlapEnd = min(candidate.end, other.end)
                guard overlapEnd > overlapStart else { return false }

                let overlapLength = overlapEnd - overlapStart
                let overlapRatio = Double(overlapLength) / Double(candidateLength)
                guard overlapRatio >= 0.75 else { return false }

                if other.category != "custom_identifier" {
                    return true
                }

                return normalizedComparableText(other.text).contains(normalizedComparableText(candidate.text))
            }
        }
    }

    nonisolated private static func mergeEquivalentSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        var groups: [String: [DetectedSpan]] = [:]
        var order: [String] = []

        for span in spans {
            let key = equivalentSpanKey(span)
            if groups[key] == nil {
                groups[key] = []
                order.append(key)
            }
            groups[key, default: []].append(span)
        }

        return order.compactMap { key in
            guard let group = groups[key], let primary = preferredSpan(in: group) else { return nil }
            let mergedSource = mergedSource(for: group)
            let mergedConfidence = group.map(\.confidence).max() ?? primary.confidence
            return DetectedSpan(
                category: primary.category,
                text: primary.text,
                start: primary.start,
                end: primary.end,
                confidence: mergedConfidence,
                source: mergedSource
            )
        }
    }

    nonisolated private static func preferredSpan(in group: [DetectedSpan]) -> DetectedSpan? {
        group.max { lhs, rhs in
            spanRank(lhs) < spanRank(rhs)
        }
    }

    nonisolated private static func spanRank(_ span: DetectedSpan) -> Int {
        var rank = 0
        if span.category != "custom_identifier" { rank += 100 }
        switch span.source {
        case .model: rank += 30
        case .mixed: rank += 20
        case .pattern: rank += 10
        }
        rank += Int(span.confidence * 10)
        return rank
    }

    nonisolated private static func mergedSource(for group: [DetectedSpan]) -> DetectionSource {
        let sources = Set(group.map(\.source))
        if sources.count > 1 || sources.contains(.mixed) {
            return .mixed
        }
        return group.first?.source ?? .pattern
    }

    nonisolated private static func exactSpanKey(_ span: DetectedSpan) -> String {
        let textKey = span.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [
            span.category,
            span.source.rawValue,
            "\(span.start)",
            "\(span.end)",
            textKey
        ].joined(separator: "::")
    }

    nonisolated private static func equivalentSpanKey(_ span: DetectedSpan) -> String {
        let textKey = span.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [
            "\(span.start)",
            "\(span.end)",
            textKey
        ].joined(separator: "::")
    }

    nonisolated private static func normalizedComparableText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    nonisolated private static func placeholderize(text: String, spans: [DetectedSpan]) -> TextAnonymizationResult {
        let selectedSpans = selectNonOverlappingSpans(spans)

        var assignedPlaceholders: [String: String] = [:]
        var placeholderByKey: [String: String] = [:]
        var placeholderCounters: [String: Int] = [:]
        var anonymizedText = text

        for span in selectedSpans.sorted(by: { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end > rhs.end }
            return lhs.start > rhs.start
        }) {
            guard span.start >= 0, span.end <= anonymizedText.count, span.end > span.start else { continue }

            let categoryBase = placeholderBase(for: span.category)
            let mappingKey = placeholderMappingKey(for: span)
            let placeholder: String

            if let existing = placeholderByKey[mappingKey] {
                placeholder = existing
            } else {
                let nextIndex = (placeholderCounters[categoryBase] ?? 0) + 1
                placeholderCounters[categoryBase] = nextIndex
                placeholder = "[\(categoryBase)_\(nextIndex)]"
                placeholderByKey[mappingKey] = placeholder
                assignedPlaceholders[placeholder] = span.text
            }

            let startIndex = anonymizedText.index(anonymizedText.startIndex, offsetBy: span.start)
            let endIndex = anonymizedText.index(anonymizedText.startIndex, offsetBy: span.end)
            anonymizedText.replaceSubrange(startIndex..<endIndex, with: placeholder)
        }

        return TextAnonymizationResult(
            anonymizedText: anonymizedText,
            replacementCount: selectedSpans.count,
            placeholders: assignedPlaceholders
        )
    }

    nonisolated private static func selectNonOverlappingSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        let sorted = spans.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let lhsLength = lhs.end - lhs.start
            let rhsLength = rhs.end - rhs.start
            if lhsLength != rhsLength { return lhsLength > rhsLength }
            return lhs.confidence > rhs.confidence
        }

        var accepted: [DetectedSpan] = []
        for candidate in sorted {
            guard candidate.end > candidate.start else { continue }
            let overlaps = accepted.contains { existing in
                max(candidate.start, existing.start) < min(candidate.end, existing.end)
            }
            if !overlaps {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    nonisolated private static func placeholderBase(for category: String) -> String {
        switch category {
        case "private_person": return "NAME"
        case "private_address": return "ADRESSE"
        case "private_date": return "DATUM"
        case "private_email": return "EMAIL"
        case "private_phone": return "TELEFON"
        case "account_number": return "NUMMER"
        case "secret": return "GEHEIM"
        case "custom_identifier": return "PLATZHALTER"
        default:
            let compact = category
                .uppercased()
                .folding(options: [.diacriticInsensitive], locale: .current)
                .replacingOccurrences(of: "PRIVATE_", with: "")
                .replacingOccurrences(of: "[^A-Z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return compact.isEmpty ? "PII" : compact
        }
    }

    nonisolated private static func placeholderMappingKey(for span: DetectedSpan) -> String {
        let normalizedText = span.text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(placeholderBase(for: span.category))::\(normalizedText)"
    }

    nonisolated private static func restorePlaceholders(in text: String, placeholders: [String: String]) -> TextRestorationResult {
        guard !placeholders.isEmpty else {
            return TextRestorationResult(restoredText: text, replacementCount: 0, unresolvedPlaceholders: [], suspiciousTokens: [])
        }

        var restoredText = text
        var replacementCount = 0

        let orderedPlaceholders = placeholders.keys.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs < rhs }
            return lhs.count > rhs.count
        }

        for placeholder in orderedPlaceholders {
            guard let originalValue = placeholders[placeholder] else { continue }
            let pattern = placeholderRegexPattern(for: placeholder)

            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(restoredText.startIndex..<restoredText.endIndex, in: restoredText)
            let matches = regex.matches(in: restoredText, range: range)
            guard !matches.isEmpty else { continue }

            replacementCount += matches.count
            restoredText = regex.stringByReplacingMatches(in: restoredText, range: range, withTemplate: originalValue)
        }

        let unresolved = orderedPlaceholders.filter { placeholder in
            let pattern = placeholderRegexPattern(for: placeholder)
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(restoredText.startIndex..<restoredText.endIndex, in: restoredText)
            return regex.firstMatch(in: restoredText, range: range) != nil
        }

        let suspiciousTokens = detectSuspiciousPlaceholderTokens(in: restoredText, expectedPlaceholders: orderedPlaceholders)

        return TextRestorationResult(
            restoredText: restoredText,
            replacementCount: replacementCount,
            unresolvedPlaceholders: unresolved,
            suspiciousTokens: suspiciousTokens
        )
    }

    nonisolated private static func placeholderRegexPattern(for placeholder: String) -> String {
        let rawKey = placeholder.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let pieces = rawKey.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2 else {
            let escaped = NSRegularExpression.escapedPattern(for: rawKey)
            return "(?i)\\[?\\s*\(escaped)\\s*\\]?"
        }

        let category = NSRegularExpression.escapedPattern(for: String(pieces[0]))
        let index = NSRegularExpression.escapedPattern(for: String(pieces[1]))
        return "(?i)\\[?\\s*\(category)\\s*[-_ ]\\s*\(index)\\s*\\]?"
    }

    nonisolated private static func canonicalPlaceholderToken(_ token: String) -> String {
        token
            .uppercased()
            .replacingOccurrences(of: "[\\[\\]\\s-]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    nonisolated private static func detectSuspiciousPlaceholderTokens(in text: String, expectedPlaceholders: [String]) -> [String] {
        let expectedCanonical = Set(expectedPlaceholders.map {
            canonicalPlaceholderToken($0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
        })

        let pattern = "(?i)\\[?\\s*[A-ZÄÖÜa-zäöü]+\\s*[-_ ]\\s*\\d+\\s*\\]?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var suspicious: [String] = []
        var seen = Set<String>()

        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            let canonical = canonicalPlaceholderToken(token)
            guard expectedCanonical.contains(canonical), seen.insert(token).inserted else { continue }
            suspicious.append(token)
        }

        return suspicious.sorted()
    }

    private func ensureCacheDirectoryExists() {
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    private static func persistClipboardSession(_ session: ClipboardAnonymizationSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: lastClipboardSessionKey)
        defaults.removeObject(forKey: legacyLastClipboardSessionKey)
    }

    private static func loadPersistedClipboardSession() -> ClipboardAnonymizationSession? {
        let defaults = UserDefaults.standard
        let isUsingLegacyValue = defaults.data(forKey: lastClipboardSessionKey) == nil
        guard let data =
                defaults.data(forKey: lastClipboardSessionKey) ??
                defaults.data(forKey: legacyLastClipboardSessionKey)
        else {
            return nil
        }

        do {
            let session = try JSONDecoder().decode(ClipboardAnonymizationSession.self, from: data)
            if isUsingLegacyValue {
                persistClipboardSession(session)
            }
            return session
        } catch {
            defaults.removeObject(forKey: lastClipboardSessionKey)
            defaults.removeObject(forKey: legacyLastClipboardSessionKey)
            return nil
        }
    }
}

enum HMDError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

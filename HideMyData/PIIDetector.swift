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

            if candidate.category == "private_person",
               isPartialPersonWithinConjoinedName(candidate, in: candidates) {
                return false
            }

            if candidate.category == "private_person",
               looksLikeRepeatedHonorificPersonNoise(candidate.snippet),
               candidates.contains(where: { other in
                   guard !areSameCandidate(candidate, other),
                         other.category == "private_person",
                         other.pageIndex == candidate.pageIndex,
                         !looksLikeRepeatedHonorificPersonNoise(other.snippet)
                   else { return false }
                   return rectGroupsOverlap(candidate.rects, other.rects)
               }) {
                return false
            }

            if candidate.category == "private_address",
               looksLikeCompanyAddressBlock(candidate.snippet) {
                return false
            }

            if candidate.category == "private_address",
               looksLikeLeadingConjunctionAddressTail(candidate.snippet) {
                return false
            }

            if candidate.category == "private_address",
               looksLikeStreetAddressWithLeadingPersonNoise(candidate.snippet),
               candidates.contains(where: { other in
                   guard !areSameCandidate(candidate, other),
                         other.category == "private_person",
                         other.pageIndex == candidate.pageIndex
                   else { return false }
                   return rectGroupsOverlap(candidate.rects, other.rects)
               }) {
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
                   (looksLikeGermanPostalCity(candidate.snippet) || looksLikeGermanStreetAddress(candidate.snippet)),
                   (addressLikelyContainsPersonTail(other.snippet) || looksLikeStreetAddressWithLeadingPersonNoise(other.snippet)) {
                    return false
                }

                if candidate.category == "private_person",
                   other.category == "private_person",
                   looksLikeRepeatedHonorificPersonNoise(other.snippet) {
                    return false
                }

                if candidate.category == "private_person",
                   other.category == "private_address",
                   (looksLikeStreetAddressWithLeadingPersonNoise(other.snippet) ||
                    addressLikelyContainsPersonTail(other.snippet)) {
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
        let pattern = #"(?i)^(?:D\s*-\s*)?\d{5}\s+[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.]+(?:[ -][A-Za-zÄÖÜäöüß.]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeGermanStreetAddress(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)\b(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*\s+){0,3}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
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

    private static func looksLikeStreetAddressWithLeadingPersonNoise(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeGermanStreetAddress(cleaned) else { return false }
        let pattern = #"(?i)^(?:[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+){2,}(?:[A-ZÄÖÜa-zäöüß][A-Za-zÄÖÜäöüß.\-]*(?:straße|str\.|strasse)|weg|allee|platz|gasse|ring|ufer|steig|steige)\s*\d+[A-Za-z]?\b"#
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

    private static func looksLikeLeadingConjunctionAddressTail(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeGermanStreetAddress(cleaned) else { return false }

        let pattern = #"(?i)^und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){1,2}\s+"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
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

    private static func isPartialPersonWithinConjoinedName(
        _ candidate: ReviewFindingCandidate,
        in candidates: [ReviewFindingCandidate]
    ) -> Bool {
        let normalizedCandidate = normalized(candidate.snippet)
        guard !normalizedCandidate.isEmpty,
              !looksLikeConjoinedCoupleName(candidate.snippet)
        else { return false }

        let candidateBounds = union(of: candidate.rects)
        guard !candidateBounds.isNull else { return false }

        return candidates.contains { other in
            guard !areSameCandidate(candidate, other),
                  other.category == "private_person",
                  other.pageIndex == candidate.pageIndex,
                  looksLikeConjoinedCoupleName(other.snippet)
            else { return false }

            let normalizedOther = normalized(other.snippet)
            guard normalizedOther.count > normalizedCandidate.count,
                  normalizedOther.contains(normalizedCandidate)
            else { return false }

            let otherBounds = union(of: other.rects)
            guard !otherBounds.isNull else { return false }

            if rectGroupsOverlap(candidate.rects, other.rects) {
                return true
            }

            let verticalGap = gapBetween(candidateBounds.minY...candidateBounds.maxY, otherBounds.minY...otherBounds.maxY)
            let horizontalGap = gapBetween(candidateBounds.minX...candidateBounds.maxX, otherBounds.minX...otherBounds.maxX)
            return verticalGap <= 10 && horizontalGap <= 60
        }
    }

    private static func looksLikeConjoinedCoupleName(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\b[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+und\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+\b"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeRepeatedHonorificPersonNoise(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:herr|frau)\s+(?:herr|frau)\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+(?:\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]+){0,2}$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
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
    let diagnostics: [String]
    let previewDiagnostics: [String]
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

enum DetectionDocumentClass: String, Sendable {
    case general
    case invoice
    case taxNotice
    case contactBankPage
    case standardizedForm

    var label: String {
        switch self {
        case .general: return "Allgemeines Dokument"
        case .invoice: return "Rechnung oder Vertragsschreiben"
        case .taxNotice: return "Steuer- oder Behördenpost"
        case .contactBankPage: return "Kontakt- oder Bankseite"
        case .standardizedForm: return "Formular oder Standardbogen"
        }
    }
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
    private static let modelCacheSchemaVersion = "v2"

    private static func defaultCacheRoot() -> URL {
        PIIDetectorModelCacheSupport.defaultCacheRoot(schemaVersion: modelCacheSchemaVersion)
    }

    private static func modelDirectory(in cacheRoot: URL) -> URL {
        PIIDetectorModelCacheSupport.modelDirectory(
            in: cacheRoot,
            modelRepoID: Self.modelRepoID,
            modelRevision: Self.modelRevision
        )
    }

    private static func readyMarkerURL(in cacheRoot: URL) -> URL {
        PIIDetectorModelCacheSupport.readyMarkerURL(
            in: cacheRoot,
            modelRepoID: Self.modelRepoID,
            modelRevision: Self.modelRevision
        )
    }

    private static func sanitizedModelRepoComponent() -> String {
        PIIDetectorModelCacheSupport.sanitizedModelRepoComponent(modelRepoID)
    }

    static func cleanupLegacyModelVersions() throws -> Int {
        try PIIDetectorModelCacheSupport.cleanupLegacyModelVersions(
            schemaVersion: modelCacheSchemaVersion,
            modelRepoID: modelRepoID,
            modelRevision: modelRevision
        )
    }

    static func legacyModelVersionCount() -> Int {
        PIIDetectorModelCacheSupport.legacyModelVersionCount(
            schemaVersion: modelCacheSchemaVersion,
            modelRepoID: modelRepoID,
            modelRevision: modelRevision
        )
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
        case .failed(let message): message
        }
    }

    private static func downloadStatus(downloaded: Int64, total: Int64) -> String {
        PIIDetectorModelCacheSupport.downloadStatus(downloaded: downloaded, total: total)
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
            phase = .failed("Der Modelldownload konnte nicht abgeschlossen werden. Prüfe bitte deine Verbindung und versuche es erneut. Details: \(error.localizedDescription)")
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
            phase = .failed("Das lokale Modell konnte nicht geladen werden. Bitte versuche den Download erneut oder starte die App noch einmal. Details: \(error.localizedDescription)")
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
                let patternDetection = PatternMatcher.detectWithDiagnostics(text)
                let supplementalSpans = Self.supplementalClipboardSpans(in: text)
                let postProcessed = Self.postProcessSpans(modelSpans + patternDetection.spans + supplementalSpans, in: text)
                Self.printPatternDiagnostics(
                    patternDetection.diagnostics,
                    postProcessed: postProcessed,
                    in: text
                )
                return .success(postProcessed)
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

    nonisolated static func visiblePatternDiagnostics(for text: String) -> [String] {
        let detection = PatternMatcher.detectWithDiagnostics(text)
        let postProcessed = postProcessSpans(detection.spans, in: text)
        return PIIDetectorPatternDiagnosticsSupport.patternDiagnosticsLines(
            detection.diagnostics,
            postProcessed: postProcessed,
            in: text
        )
    }

    // MARK: - Helpers

    private func runOnBackground<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    nonisolated static func classifyDocumentText(_ text: String) -> DetectionDocumentClass {
        PIIDetectorSupplementalClipboardSupport.classifyDocumentText(text)
    }

    nonisolated private static func postProcessSpans(_ spans: [DetectedSpan], in text: String) -> [DetectedSpan] {
        let sanitized = sanitizeSpans(spans)
        let deduplicated = deduplicateExactSpans(sanitized)
        let merged = mergeEquivalentSpans(deduplicated)
        let withoutConjoinedFragments = suppressConjoinedNameFragments(merged)
        let withoutLeadingAddressTails = suppressLeadingConjunctionAddressSpans(withoutConjoinedFragments)
        let withoutLegalBoilerplate = suppressLegalBoilerplateFalsePositives(withoutLeadingAddressTails, in: text)
        return suppressContainedCustomIdentifierSpans(withoutLegalBoilerplate)
    }

    nonisolated private static func supplementalClipboardSpans(in text: String) -> [DetectedSpan] {
        PIIDetectorSupplementalClipboardSupport.supplementalClipboardSpans(in: text)
    }

    nonisolated private static func supplementalInlinePersonSpans(in text: String) -> [DetectedSpan] {
        PIIDetectorSupplementalClipboardSupport.supplementalInlinePersonSpans(in: text)
    }

    nonisolated private static func looksLikeStandaloneFieldSequence(in text: String) -> Bool {
        PIIDetectorSupplementalClipboardSupport.looksLikeStandaloneFieldSequence(in: text)
    }

    nonisolated private static func sanitizeSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.sanitizeSpans(spans)
    }

    nonisolated private static func cleanedSpanText(_ text: String) -> String {
        PIIDetectorSpanSanitizationSupport.cleanedSpanText(text)
    }

    nonisolated private static func sanitizedSpanText(_ text: String, category: String) -> String {
        PIIDetectorSpanSanitizationSupport.sanitizedSpanText(text, category: category)
    }

    nonisolated private static func sanitizeAddressFieldArtifacts(in text: String) -> String {
        PIIDetectorSpanSanitizationSupport.sanitizeAddressFieldArtifacts(in: text)
    }

    nonisolated private static func sanitizedCategory(for category: String, text: String) -> String {
        PIIDetectorSpanSanitizationSupport.sanitizedCategory(for: category, text: text)
    }

    nonisolated private static func shouldDropSpan(category: String, text: String, source: DetectionSource) -> Bool {
        PIIDetectorSpanSanitizationSupport.shouldDropSpan(category: category, text: text, source: source)
    }

    nonisolated private static func looksLikePostalCity(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikePostalCity(text)
    }

    nonisolated private static func looksLikeGermanStreetAddress(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeGermanStreetAddress(text)
    }

    nonisolated private static func looksLikeStreetNameOnlyLine(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeStreetNameOnlyLine(text)
    }

    nonisolated private static func looksLikeHouseNumberOnlyLine(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeHouseNumberOnlyLine(text)
    }

    nonisolated private static func looksLikePostalCodeOnlyLine(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikePostalCodeOnlyLine(text)
    }

    nonisolated private static func looksLikeCityNameOnlyLine(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeCityNameOnlyLine(text)
    }

    nonisolated private static func looksLikeAddressBlock(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeAddressBlock(text)
    }

    nonisolated private static func hasLeadingSentenceFragmentBeforeStreetAddress(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.hasLeadingSentenceFragmentBeforeStreetAddress(text)
    }

    nonisolated private static func looksLikeCompanyAddressBlock(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeCompanyAddressBlock(text)
    }

    nonisolated private static func personSpanContainsAddressOrContactTail(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.personSpanContainsAddressOrContactTail(text)
    }

    nonisolated private static func looksLikeHonorificStreetCombo(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeHonorificStreetCombo(text)
    }

    nonisolated private static func looksLikeLeadingConjunctionAddressTail(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeLeadingConjunctionAddressTail(text)
    }

    nonisolated private static func looksLikeConjoinedCoupleName(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeConjoinedCoupleName(text)
    }

    nonisolated private static func looksLikeNameishWord(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeNameishWord(text)
    }

    nonisolated private static func looksLikeTaxOfficeHeader(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeTaxOfficeHeader(text)
    }

    nonisolated private static func looksLikeOrganizationSnippet(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeOrganizationSnippet(text)
    }

    nonisolated private static func isDocumentNoise(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.isDocumentNoise(text)
    }

    nonisolated private static func looksLikeTermsAndConditionsDocument(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeTermsAndConditionsDocument(text)
    }

    nonisolated private static func looksLikeLegalBoilerplateHeading(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikeLegalBoilerplateHeading(text)
    }

    nonisolated private static func looksLikePlausiblePersonName(_ text: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.looksLikePlausiblePersonName(text)
    }

    nonisolated private static func deduplicateExactSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.deduplicateExactSpans(spans)
    }

    nonisolated private static func suppressConjoinedNameFragments(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.suppressConjoinedNameFragments(spans)
    }

    nonisolated private static func suppressLeadingConjunctionAddressSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.suppressLeadingConjunctionAddressSpans(spans)
    }

    nonisolated private static func suppressLegalBoilerplateFalsePositives(_ spans: [DetectedSpan], in text: String) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.suppressLegalBoilerplateFalsePositives(spans, in: text)
    }

    nonisolated private static func suppressContainedCustomIdentifierSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.suppressContainedCustomIdentifierSpans(spans)
    }

    nonisolated private static func shouldPreserveStrongCustomIdentifier(_ candidate: DetectedSpan, inside other: DetectedSpan) -> Bool {
        PIIDetectorSpanSanitizationSupport.shouldPreserveStrongCustomIdentifier(candidate, inside: other)
    }

    nonisolated private static func isHonorificWrappedPerson(candidate: String, wrapper: String) -> Bool {
        PIIDetectorSpanSanitizationSupport.isHonorificWrappedPerson(candidate: candidate, wrapper: wrapper)
    }

    nonisolated private static func mergeEquivalentSpans(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        PIIDetectorSpanSanitizationSupport.mergeEquivalentSpans(spans)
    }

    nonisolated private static func preferredSpan(in group: [DetectedSpan]) -> DetectedSpan? {
        PIIDetectorSpanSanitizationSupport.preferredSpan(in: group)
    }

    nonisolated private static func spanRank(_ span: DetectedSpan) -> Int {
        PIIDetectorSpanSanitizationSupport.spanRank(span)
    }

    nonisolated private static func mergedSource(for group: [DetectedSpan]) -> DetectionSource {
        PIIDetectorSpanSanitizationSupport.mergedSource(for: group)
    }

    nonisolated private static func exactSpanKey(_ span: DetectedSpan) -> String {
        PIIDetectorSpanSanitizationSupport.exactSpanKey(span)
    }

    nonisolated private static func equivalentSpanKey(_ span: DetectedSpan) -> String {
        PIIDetectorSpanSanitizationSupport.equivalentSpanKey(span)
    }

    nonisolated private static func normalizedComparableText(_ text: String) -> String {
        PIIDetectorSpanSanitizationSupport.normalizedComparableText(text)
    }

    nonisolated private static func placeholderize(text: String, spans: [DetectedSpan]) -> TextAnonymizationResult {
        PIIDetectorPlaceholderSupport.placeholderize(text: text, spans: spans)
    }

    nonisolated private static func restorePlaceholders(in text: String, placeholders: [String: String]) -> TextRestorationResult {
        PIIDetectorPlaceholderSupport.restorePlaceholders(in: text, placeholders: placeholders)
    }

    nonisolated private static func printPatternDiagnostics(
        _ diagnostics: PatternMatcher.Diagnostics,
        postProcessed: [DetectedSpan],
        in text: String
    ) {
        PIIDetectorPatternDiagnosticsSupport.printPatternDiagnostics(
            diagnostics,
            postProcessed: postProcessed,
            in: text
        )
    }

    nonisolated private static func patternDiagnosticsLines(
        _ diagnostics: PatternMatcher.Diagnostics,
        postProcessed: [DetectedSpan],
        in text: String
    ) -> [String] {
        PIIDetectorPatternDiagnosticsSupport.patternDiagnosticsLines(
            diagnostics,
            postProcessed: postProcessed,
            in: text
        )
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

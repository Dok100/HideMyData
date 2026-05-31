import Foundation
import CoreGraphics

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
        case .addressBlock, .contact:
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

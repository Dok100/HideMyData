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

            return !candidates.contains { other in
                guard !areSameCandidate(candidate, other),
                      candidate.pageIndex == other.pageIndex
                else { return false }

                let normalizedOther = normalized(other.snippet)
                guard !normalizedOther.isEmpty,
                      normalizedOther.count > normalizedCandidate.count,
                      normalizedOther.contains(normalizedCandidate)
                else { return false }

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

        for candidate in cluster.candidates {
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
    private static let lastClipboardSessionKey = "HMD.lastClipboardSession"

    static let modelRepoID = "OpenMed/privacy-filter-mlx-8bit"
    static let modelRevision = "4c9836d"
    static let modelURL = URL(string: "https://huggingface.co/\(modelRepoID)/tree/\(modelRevision)")!

    private static func defaultCacheRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("HideMyData", isDirectory: true)
            .appendingPathComponent("ModelCache", isDirectory: true)
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
        let deduplicated = deduplicateExactSpans(spans)
        let merged = mergeEquivalentSpans(deduplicated)
        return suppressContainedCustomIdentifierSpans(merged)
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
        UserDefaults.standard.set(data, forKey: lastClipboardSessionKey)
    }

    private static func loadPersistedClipboardSession() -> ClipboardAnonymizationSession? {
        guard let data = UserDefaults.standard.data(forKey: lastClipboardSessionKey),
              let session = try? JSONDecoder().decode(ClipboardAnonymizationSession.self, from: data)
        else {
            return nil
        }
        return session
    }
}

enum HMDError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

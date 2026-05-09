import Foundation
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

    private var openmed: OpenMed?

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

    private func ensureCacheDirectoryExists() {
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }
}

enum HMDError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

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
        let readyMarkerURL = Self.readyMarkerURL(in: Self.defaultCacheRoot())
        self.phase = PIIDetectorLifecycleSupport.initialPhase(readyMarkerURL: readyMarkerURL)
        self.lastClipboardSession = Self.loadPersistedClipboardSession(
            key: Self.lastClipboardSessionKey,
            legacyKey: Self.legacyLastClipboardSessionKey
        )
    }

    var statusText: String {
        PIIDetectorLifecycleSupport.statusText(for: phase)
    }

    var isReady: Bool {
        PIIDetectorLifecycleSupport.isReady(phase)
    }

    var isBusy: Bool {
        PIIDetectorLifecycleSupport.isBusy(phase)
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
            phase = .failed(PIIDetectorLifecycleSupport.modelDownloadFailureMessage(for: error))
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
            phase = .failed(PIIDetectorLifecycleSupport.modelLoadFailureMessage(for: error))
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
            PIIDetectorInferenceSupport.detect(
                text,
                model: model,
                supplementalSpans: Self.supplementalClipboardSpans(in:),
                postProcess: Self.postProcessSpans(_:in:),
                printDiagnostics: { diagnostics, postProcessed, sourceText in
                    Self.printPatternDiagnostics(
                        diagnostics,
                        postProcessed: postProcessed,
                        in: sourceText
                    )
                }
            )
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
            let session = PIIDetectorInferenceSupport.makeClipboardSession(
                originalText: text,
                anonymizationResult: result
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
        PIIDetectorInferenceSupport.visiblePatternDiagnostics(
            for: text,
            postProcess: Self.postProcessSpans(_:in:),
            diagnosticsLines: { diagnostics, postProcessed, sourceText in
                PIIDetectorPatternDiagnosticsSupport.patternDiagnosticsLines(
                    diagnostics,
                    postProcessed: postProcessed,
                    in: sourceText
                )
            }
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
        PIIDetectorClipboardSessionSupport.persistClipboardSession(
            session,
            key: lastClipboardSessionKey,
            legacyKey: legacyLastClipboardSessionKey
        )
    }

    private static func loadPersistedClipboardSession(key: String, legacyKey: String) -> ClipboardAnonymizationSession? {
        PIIDetectorClipboardSessionSupport.loadPersistedClipboardSession(
            key: key,
            legacyKey: legacyKey
        )
    }
}

enum HMDError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

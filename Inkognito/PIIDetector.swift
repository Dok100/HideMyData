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
        self.lastClipboardSession = PIIDetectorClipboardSessionSupport.loadPersistedClipboardSession(
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
        await PIIDetectorModelLifecycleSupport.loadIfCached(
            phase: phase,
            cacheRoot: cacheRoot,
            loadCachedModel: loadCachedModel
        )
    }

    func startDownload() async {
        await PIIDetectorModelLifecycleSupport.startDownload(
            modelRepoID: Self.modelRepoID,
            modelRevision: Self.modelRevision,
            cacheRoot: cacheRoot,
            updatePhase: { [weak self] in self?.phase = $0 },
            loadCachedModel: loadCachedModel
        )
    }

    private func loadCachedModel() async {
        await PIIDetectorModelLifecycleSupport.loadCachedModel(
            readyMarkerURL: readyMarkerURL,
            modelDirectory: modelDirectory,
            updatePhase: { [weak self] in self?.phase = $0 },
            assignModel: { [weak self] in self?.openmed = $0 },
            warmUp: warmUp
        )
    }

    private func warmUp() async {
        await PIIDetectorModelLifecycleSupport.warmUp(
            model: openmed,
            updatePhase: { [weak self] in self?.phase = $0 }
        )
    }

    // MARK: - Inference

    func detect(_ text: String) async -> Result<[DetectedSpan], Error> {
        await PIIDetectorModelLifecycleSupport.performDetection(
            model: openmed,
            currentPhase: phase,
            updatePhase: { [weak self] in self?.phase = $0 }
        ) { model in
            await PIIDetectorModelLifecycleSupport.runOnBackground {
                PIIDetectorInferenceSupport.detect(
                    text,
                    model: model,
                    supplementalSpans: PIIDetectorSupplementalClipboardSupport.supplementalClipboardSpans(in:),
                    postProcess: PIIDetectorInferenceSupport.postProcessSpans(_:in:),
                    printDiagnostics: PIIDetectorPatternDiagnosticsSupport.printPatternDiagnostics(_:postProcessed:in:)
                )
            }
        }
    }

    func anonymizeText(_ text: String) async -> Result<TextAnonymizationResult, Error> {
        await PIIDetectorAnonymizationSupport.anonymizeText(text, detect: detect)
    }

    func anonymizeClipboardText(_ text: String) async -> Result<ClipboardAnonymizationSession, Error> {
        await PIIDetectorAnonymizationSupport.anonymizeClipboardText(
            text,
            detect: detect,
            assignSession: { [weak self] in self?.lastClipboardSession = $0 },
            persistSession: {
                PIIDetectorClipboardSessionSupport.persistClipboardSession(
                    $0,
                    key: Self.lastClipboardSessionKey,
                    legacyKey: Self.legacyLastClipboardSessionKey
                )
            }
        )
    }

    func restoreText(_ text: String) -> TextRestorationResult? {
        PIIDetectorClipboardSessionSupport.restoreText(text, session: lastClipboardSession)
    }
}

enum HMDError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

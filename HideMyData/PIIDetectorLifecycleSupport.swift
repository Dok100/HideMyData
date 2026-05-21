import Foundation
@preconcurrency import OpenMedKit

enum PIIDetectorLifecycleSupport {
    @MainActor
    static func initialPhase(readyMarkerURL: URL) -> PIIDetector.Phase {
        FileManager.default.fileExists(atPath: readyMarkerURL.path) ? .loadingModel : .needsDownload
    }

    static func statusText(for phase: PIIDetector.Phase) -> String {
        switch phase {
        case .needsDownload:
            return "Modell nicht heruntergeladen"
        case .downloading(let downloaded, let total):
            return PIIDetectorModelCacheSupport.downloadStatus(downloaded: downloaded, total: total)
        case .loadingModel:
            return "Modell wird geladen…"
        case .warmingUp:
            return "Modell wird vorbereitet…"
        case .ready:
            return "Bereit"
        case .running:
            return "Wird ausgeführt…"
        case .failed(let message):
            return message
        }
    }

    static func isReady(_ phase: PIIDetector.Phase) -> Bool {
        switch phase {
        case .ready, .running:
            return true
        default:
            return false
        }
    }

    static func isBusy(_ phase: PIIDetector.Phase) -> Bool {
        switch phase {
        case .loadingModel, .warmingUp, .running, .downloading:
            return true
        default:
            return false
        }
    }

    static func modelDownloadFailureMessage(for error: Error) -> String {
        "Der Modelldownload konnte nicht abgeschlossen werden. Prüfe bitte deine Verbindung und versuche es erneut. Details: \(error.localizedDescription)"
    }

    static func modelLoadFailureMessage(for error: Error) -> String {
        "Das lokale Modell konnte nicht geladen werden. Bitte versuche den Download erneut oder starte die App noch einmal. Details: \(error.localizedDescription)"
    }
}

enum PIIDetectorModelLifecycleSupport {
    @MainActor
    static func loadIfCached(
        phase: PIIDetector.Phase,
        cacheRoot: URL,
        loadCachedModel: @escaping @MainActor () async -> Void
    ) async {
        ensureCacheDirectoryExists(at: cacheRoot)
        if case .loadingModel = phase {
            await loadCachedModel()
        }
    }

    @MainActor
    static func startDownload(
        modelRepoID: String,
        modelRevision: String,
        cacheRoot: URL,
        updatePhase: @escaping @MainActor (PIIDetector.Phase) -> Void,
        loadCachedModel: @escaping @MainActor () async -> Void
    ) async {
        ensureCacheDirectoryExists(at: cacheRoot)
        updatePhase(.downloading(downloaded: 0, total: 0))

        let downloader = ModelDownloader(
            repoID: modelRepoID,
            revision: modelRevision,
            cacheRoot: cacheRoot
        )
        downloader.onProgress = { downloaded, total in
            updatePhase(.downloading(downloaded: downloaded, total: total))
        }

        do {
            _ = try await downloader.download()
            await loadCachedModel()
        } catch {
            updatePhase(.failed(PIIDetectorLifecycleSupport.modelDownloadFailureMessage(for: error)))
        }
    }

    @MainActor
    static func loadCachedModel(
        readyMarkerURL: URL,
        modelDirectory: URL,
        updatePhase: @escaping @MainActor (PIIDetector.Phase) -> Void,
        assignModel: @escaping @MainActor (OpenMed?) -> Void,
        warmUp: @escaping @MainActor () async -> Void
    ) async {
        updatePhase(.loadingModel)

        do {
            guard FileManager.default.fileExists(atPath: readyMarkerURL.path) else {
                updatePhase(.needsDownload)
                return
            }

            assignModel(try OpenMed(backend: .mlx(modelDirectoryURL: modelDirectory)))
            await warmUp()
        } catch {
            updatePhase(.failed(PIIDetectorLifecycleSupport.modelLoadFailureMessage(for: error)))
        }
    }

    @MainActor
    static func warmUp(
        model: OpenMed?,
        updatePhase: @escaping @MainActor (PIIDetector.Phase) -> Void
    ) async {
        updatePhase(.warmingUp)
        _ = await runOnBackground {
            try? model?.extractPII("Aufwärmen.", confidenceThreshold: 0.5, useSmartMerging: false)
        }
        updatePhase(.ready)
    }

    static func runOnBackground<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    @MainActor
    static func performDetection<T: Sendable>(
        model: OpenMed?,
        currentPhase: PIIDetector.Phase,
        updatePhase: @escaping @MainActor (PIIDetector.Phase) -> Void,
        operation: @escaping @MainActor (OpenMed) async -> Result<T, Error>
    ) async -> Result<T, Error> {
        guard let model else {
            return .failure(HMDError.message("Erkennung ist nicht geladen"))
        }

        updatePhase(.running)
        defer { updatePhase(currentPhase) }
        return await operation(model)
    }

    private static func ensureCacheDirectoryExists(at cacheRoot: URL) {
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }
}

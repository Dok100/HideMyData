import Foundation

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

import Foundation

enum PIIDetectorAnonymizationSupport {
    @MainActor
    static func anonymizeText(
        _ text: String,
        detect: @escaping @MainActor (String) async -> Result<[DetectedSpan], Error>
    ) async -> Result<TextAnonymizationResult, Error> {
        switch await detect(text) {
        case .failure(let error):
            return .failure(error)
        case .success(let spans):
            return .success(PIIDetectorPlaceholderSupport.placeholderize(text: text, spans: spans))
        }
    }

    @MainActor
    static func anonymizeClipboardText(
        _ text: String,
        detect: @escaping @MainActor (String) async -> Result<[DetectedSpan], Error>,
        assignSession: @escaping @MainActor (ClipboardAnonymizationSession) -> Void,
        persistSession: @escaping (ClipboardAnonymizationSession) -> Void
    ) async -> Result<ClipboardAnonymizationSession, Error> {
        switch await anonymizeText(text, detect: detect) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            let session = PIIDetectorClipboardSessionSupport.makeClipboardSession(
                originalText: text,
                anonymizationResult: result
            )
            assignSession(session)
            persistSession(session)
            return .success(session)
        }
    }
}

enum PIIDetectorClipboardSessionSupport {
    static func makeClipboardSession(
        originalText: String,
        anonymizationResult: TextAnonymizationResult,
        createdAt: Date = Date()
    ) -> ClipboardAnonymizationSession {
        ClipboardAnonymizationSession(
            originalText: originalText,
            anonymizedText: anonymizationResult.anonymizedText,
            replacementCount: anonymizationResult.replacementCount,
            placeholders: anonymizationResult.placeholders,
            createdAt: createdAt
        )
    }

    static func persistClipboardSession(
        _ session: ClipboardAnonymizationSession,
        key: String,
        legacyKey: String
    ) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }

    static func loadPersistedClipboardSession(
        key: String,
        legacyKey: String
    ) -> ClipboardAnonymizationSession? {
        let defaults = UserDefaults.standard
        let isUsingLegacyValue = defaults.data(forKey: key) == nil
        guard let data = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey) else {
            return nil
        }

        do {
            let session = try JSONDecoder().decode(ClipboardAnonymizationSession.self, from: data)
            if isUsingLegacyValue {
                persistClipboardSession(session, key: key, legacyKey: legacyKey)
            }
            return session
        } catch {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: legacyKey)
            return nil
        }
    }

    static func restoreText(
        _ text: String,
        session: ClipboardAnonymizationSession?
    ) -> TextRestorationResult? {
        guard let session else { return nil }
        return PIIDetectorPlaceholderSupport.restorePlaceholders(in: text, placeholders: session.placeholders)
    }
}

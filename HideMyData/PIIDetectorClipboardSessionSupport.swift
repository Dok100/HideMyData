import Foundation

enum PIIDetectorClipboardSessionSupport {
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
}

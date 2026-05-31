import Foundation

nonisolated enum PatternStorePersistenceSupport {
    static func loadDecodedPatterns() -> [CustomPattern]? {
        guard let data = try? Data(contentsOf: storageURL()),
              let decoded = try? JSONDecoder().decode([CustomPattern].self, from: data) else {
            return nil
        }
        return decoded
    }

    static func loadPatterns() -> [CustomPattern] {
        guard let decoded = loadDecodedPatterns() else { return [] }
        return PatternStoreNormalizationSupport.sanitizedPersistedPatterns(decoded)
    }

    static func persist(_ patterns: [CustomPattern]) {
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(patterns) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func storageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateLegacyStorageIfNeeded(base: support)
        return support
            .appendingPathComponent("Inkognito", isDirectory: true)
            .appendingPathComponent("custom-patterns.json")
    }

    static func legacyStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("HideMyData", isDirectory: true)
            .appendingPathComponent("custom-patterns.json")
    }

    private static func migrateLegacyStorageIfNeeded(base: URL) {
        let fm = FileManager.default
        let legacyDir = base.appendingPathComponent("HideMyData", isDirectory: true)
        let newDir = base.appendingPathComponent("Inkognito", isDirectory: true)
        let legacyFile = legacyDir.appendingPathComponent("custom-patterns.json")
        let newFile = newDir.appendingPathComponent("custom-patterns.json")

        guard fm.fileExists(atPath: legacyFile.path),
              !fm.fileExists(atPath: newFile.path) else { return }

        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: legacyFile, to: newFile)
    }
}

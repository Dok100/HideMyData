import Foundation

enum PIIDetectorModelCacheSupport {
    nonisolated static func defaultCacheRoot(schemaVersion: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheBase = support
            .appendingPathComponent("Inkognito", isDirectory: true)
            .appendingPathComponent("ModelCache", isDirectory: true)
        migrateLegacyCacheIfNeeded(base: support, cacheBase: cacheBase, schemaVersion: schemaVersion)
        return cacheBase.appendingPathComponent(schemaVersion, isDirectory: true)
    }

    nonisolated static func modelDirectory(in cacheRoot: URL, modelRepoID: String, modelRevision: String) -> URL {
        cacheRoot
            .appendingPathComponent(modelRepoID.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
            .appendingPathComponent(modelRevision, isDirectory: true)
    }

    nonisolated static func readyMarkerURL(in cacheRoot: URL, modelRepoID: String, modelRevision: String) -> URL {
        modelDirectory(in: cacheRoot, modelRepoID: modelRepoID, modelRevision: modelRevision)
            .appendingPathComponent(".openmed-artifact-ready")
    }

    nonisolated static func sanitizedModelRepoComponent(_ modelRepoID: String) -> String {
        modelRepoID.replacingOccurrences(of: "/", with: "__")
    }

    nonisolated static func cleanupLegacyModelVersions(schemaVersion: String, modelRepoID: String, modelRevision: String) throws -> Int {
        let fm = FileManager.default
        let repoRoot = defaultCacheRoot(schemaVersion: schemaVersion)
            .appendingPathComponent(sanitizedModelRepoComponent(modelRepoID), isDirectory: true)

        guard fm.fileExists(atPath: repoRoot.path) else { return 0 }

        let revisions = try fm.contentsOfDirectory(
            at: repoRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var removedCount = 0
        for revisionDir in revisions {
            let values = try revisionDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            guard revisionDir.lastPathComponent != modelRevision else { continue }
            try fm.removeItem(at: revisionDir)
            removedCount += 1
        }

        return removedCount
    }

    nonisolated static func legacyModelVersionCount(schemaVersion: String, modelRepoID: String, modelRevision: String) -> Int {
        let fm = FileManager.default
        let repoRoot = defaultCacheRoot(schemaVersion: schemaVersion)
            .appendingPathComponent(sanitizedModelRepoComponent(modelRepoID), isDirectory: true)

        guard let revisions = try? fm.contentsOfDirectory(
            at: repoRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return revisions.reduce(into: 0) { count, url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true,
                  url.lastPathComponent != modelRevision else { return }
            count += 1
        }
    }

    nonisolated static func downloadStatus(downloaded: Int64, total: Int64) -> String {
        let downloadedStr = downloaded.formatted(.byteCount(style: .file))
        guard total > 0 else { return "Wird heruntergeladen… bisher \(downloadedStr)" }
        let totalStr = total.formatted(.byteCount(style: .file))
        let pct = (Double(downloaded) / Double(total))
            .formatted(.percent.precision(.fractionLength(0)))
        return "Wird heruntergeladen… \(downloadedStr) / \(totalStr) (\(pct))"
    }

    nonisolated private static func migrateLegacyCacheIfNeeded(base: URL, cacheBase: URL, schemaVersion: String) {
        let fm = FileManager.default
        let legacyDir = base.appendingPathComponent("HideMyData/ModelCache", isDirectory: true)
        let versionedDir = cacheBase.appendingPathComponent(schemaVersion, isDirectory: true)

        guard fm.fileExists(atPath: legacyDir.path),
              !fm.fileExists(atPath: cacheBase.path),
              !fm.fileExists(atPath: versionedDir.path) else {
            migrateSchemaCacheIfNeeded(cacheBase: cacheBase, versionedDir: versionedDir, schemaVersion: schemaVersion)
            return
        }
        try? fm.createDirectory(at: cacheBase.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: legacyDir, to: cacheBase)
        migrateSchemaCacheIfNeeded(cacheBase: cacheBase, versionedDir: versionedDir, schemaVersion: schemaVersion)
    }

    nonisolated private static func migrateSchemaCacheIfNeeded(cacheBase: URL, versionedDir: URL, schemaVersion: String) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: cacheBase.path),
              !fm.fileExists(atPath: versionedDir.path) else { return }

        try? fm.createDirectory(at: versionedDir, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(at: cacheBase, includingPropertiesForKeys: nil) else { return }

        for item in contents where item.lastPathComponent != schemaVersion {
            let destination = versionedDir.appendingPathComponent(item.lastPathComponent, isDirectory: true)
            guard !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.moveItem(at: item, to: destination)
        }
    }
}

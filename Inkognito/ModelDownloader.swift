import Foundation

@MainActor
final class ModelDownloader {
    var onProgress: ((_ downloaded: Int64, _ total: Int64) -> Void)?

    private let repoID: String
    private let revision: String
    private let cacheRoot: URL
    private let remoteBaseURL: URL

    init(repoID: String, revision: String = "main", cacheRoot: URL) {
        self.repoID = repoID
        self.revision = revision
        self.cacheRoot = cacheRoot
        self.remoteBaseURL = URL(string: "https://huggingface.co/\(repoID)/resolve/\(revision)")!
    }

    func download() async throws -> URL {
        let modelDirectory = cacheRoot
            .appendingPathComponent(sanitizedPathComponent(repoID), isDirectory: true)
            .appendingPathComponent(sanitizedPathComponent(revision), isDirectory: true)

        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let manifestURL = remoteBaseURL.appendingPathComponent("openmed-mlx.json")
        let manifestDestination = modelDirectory.appendingPathComponent("openmed-mlx.json")
        let (manifestData, _) = try await URLSession.shared.data(from: manifestURL)
        try manifestData.write(to: manifestDestination)

        let manifest = try JSONDecoder().decode(OpenMedManifest.self, from: manifestData)
        let downloadPlan = try buildDownloadPlan(from: manifest)

        onProgress?(Int64(manifestData.count), 0)

        let fileSizes = try await resolveRemoteSizes(for: downloadPlan)
        let totalSize = Int64(manifestData.count) + fileSizes.values.reduce(0, +)

        var downloadedSize = Int64(manifestData.count)
        onProgress?(downloadedSize, totalSize)

        for relativePath in downloadPlan {
            let remoteURL = remoteBaseURL.appendingPathComponent(relativePath)
            let destination = try destinationURL(for: relativePath, inside: modelDirectory)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let baseline = downloadedSize
            let tracker = DownloadStream(destination: destination) { [weak self] bytesWritten, _ in
                Task { @MainActor [weak self] in
                    self?.onProgress?(baseline + bytesWritten, totalSize)
                }
            }

            _ = try await tracker.download(from: remoteURL)
            downloadedSize += fileSizes[relativePath] ?? 0
            onProgress?(downloadedSize, totalSize)
        }

        let readyMarker = modelDirectory.appendingPathComponent(".openmed-artifact-ready")
        try Data().write(to: readyMarker)

        return modelDirectory
    }

    private func buildDownloadPlan(from manifest: OpenMedManifest) throws -> [String] {
        var files: [String] = [
            try validatedRelativePath(manifest.config_path),
            try validatedRelativePath(manifest.preferred_weights)
        ]

        if let labelMap = manifest.label_map_path {
            files.append(try validatedRelativePath(labelMap))
        }

        let tokenizerRoot = try validatedRelativePath(manifest.tokenizer.path)
        for file in manifest.tokenizer.files {
            let tokenizerFile = try validatedRelativePath(file)
            let combinedPath = tokenizerRoot == "." ? tokenizerFile : "\(tokenizerRoot)/\(tokenizerFile)"
            files.append(try validatedRelativePath(combinedPath))
        }

        return files
    }

    private func resolveRemoteSizes(for paths: [String]) async throws -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for path in paths {
            sizes[path] = try await contentLength(of: remoteBaseURL.appendingPathComponent(path))
        }
        return sizes
    }

    private func contentLength(of url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        let expectedLength = response.expectedContentLength
        return expectedLength > 0 ? expectedLength : 0
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        value.replacing("/", with: "__")
    }

    private func validatedRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty else {
            throw ModelDownloadError.invalidManifestPath(path)
        }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else {
            throw ModelDownloadError.invalidManifestPath(path)
        }

        var cleanedComponents: [String] = []
        for component in normalized.split(separator: "/", omittingEmptySubsequences: false) {
            let part = String(component)
            if part.isEmpty || part == "." {
                continue
            }
            if part == ".." {
                throw ModelDownloadError.invalidManifestPath(path)
            }
            cleanedComponents.append(part)
        }

        return cleanedComponents.isEmpty ? "." : cleanedComponents.joined(separator: "/")
    }

    private func destinationURL(for relativePath: String, inside modelDirectory: URL) throws -> URL {
        let destination = modelDirectory.appendingPathComponent(relativePath)
        let rootPath = modelDirectory.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path

        guard destinationPath == rootPath || destinationPath.hasPrefix(rootPath + "/") else {
            throw ModelDownloadError.invalidManifestPath(relativePath)
        }

        return destination
    }
}

private struct OpenMedManifest: Decodable {
    let config_path: String
    let label_map_path: String?
    let preferred_weights: String
    let tokenizer: Tokenizer

    struct Tokenizer: Decodable {
        let path: String
        let files: [String]
    }
}

private enum ModelDownloadError: LocalizedError {
    case invalidManifestPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifestPath(let path):
            return "Das Manifest enthält einen unsicheren Pfad: \(path)"
        }
    }
}

private final class DownloadStream: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (_ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(
        destination: URL,
        onProgress: @escaping @Sendable (_ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void
    ) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.invalidateAndCancel()
    }
}

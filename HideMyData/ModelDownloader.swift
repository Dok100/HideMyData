import Foundation

@MainActor
final class ModelDownloader {
    var onProgress: ((_ downloaded: Int64, _ total: Int64) -> Void)?

    private let repoID: String
    private let revision: String
    private let cacheRoot: URL
    private let baseURL: URL

    init(repoID: String, revision: String = "main", cacheRoot: URL) {
        self.repoID = repoID
        self.revision = revision
        self.cacheRoot = cacheRoot
        self.baseURL = URL(string: "https://huggingface.co/\(repoID)/resolve/\(revision)")!
    }

    func download() async throws -> URL {
        let modelDir = cacheRoot
            .appendingPathComponent(sanitize(repoID), isDirectory: true)
            .appendingPathComponent(sanitize(revision), isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let manifestDest = modelDir.appendingPathComponent("openmed-mlx.json")
        let (manifestData, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("openmed-mlx.json"))
        try manifestData.write(to: manifestDest)
        let manifest = try JSONDecoder().decode(OpenMedManifest.self, from: manifestData)

        var files: [String] = [try validatedRelativePath(manifest.config_path)]
        if let labelMap = manifest.label_map_path {
            files.append(try validatedRelativePath(labelMap))
        }
        files.append(try validatedRelativePath(manifest.preferred_weights))
        let tokenizerBase = try validatedRelativePath(manifest.tokenizer.path)
        for f in manifest.tokenizer.files {
            let safeFile = try validatedRelativePath(f)
            let combined = tokenizerBase == "." ? safeFile : "\(tokenizerBase)/\(safeFile)"
            files.append(try validatedRelativePath(combined))
        }

        onProgress?(Int64(manifestData.count), 0)
        var sizes: [String: Int64] = [:]
        var totalSize: Int64 = Int64(manifestData.count)
        for path in files {
            let size = try await contentLength(of: baseURL.appendingPathComponent(path))
            sizes[path] = size
            totalSize += size
        }

        var cumulative: Int64 = Int64(manifestData.count)
        onProgress?(cumulative, totalSize)

        for path in files {
            let url = baseURL.appendingPathComponent(path)
            let dest = try destinationURL(for: path, in: modelDir)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

            let baseline = cumulative
            let total = totalSize
            let task = StreamingDownload(destination: dest) { [weak self] writtenForFile, _ in
                Task { @MainActor [weak self] in
                    self?.onProgress?(baseline + writtenForFile, total)
                }
            }
            _ = try await task.download(from: url)
            cumulative += sizes[path] ?? 0
            onProgress?(cumulative, totalSize)
        }

        let marker = modelDir.appendingPathComponent(".openmed-artifact-ready")
        try Data().write(to: marker)

        return modelDir
    }

    private func contentLength(of url: URL) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: req)
        let len = response.expectedContentLength
        return len > 0 ? len : 0
    }

    private func sanitize(_ s: String) -> String {
        s.replacing("/", with: "__")
    }

    private func validatedRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty else {
            throw ModelDownloadError.invalidManifestPath(path)
        }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") {
            throw ModelDownloadError.invalidManifestPath(path)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        var cleaned: [String] = []
        for component in components {
            let part = String(component)
            if part.isEmpty || part == "." {
                continue
            }
            if part == ".." {
                throw ModelDownloadError.invalidManifestPath(path)
            }
            cleaned.append(part)
        }

        guard !cleaned.isEmpty else {
            return "."
        }
        return cleaned.joined(separator: "/")
    }

    private func destinationURL(for relativePath: String, in modelDir: URL) throws -> URL {
        let dest = modelDir.appendingPathComponent(relativePath)
        let basePath = modelDir.standardizedFileURL.path
        let destPath = dest.standardizedFileURL.path
        guard destPath == basePath || destPath.hasPrefix(basePath + "/") else {
            throw ModelDownloadError.invalidManifestPath(relativePath)
        }
        return dest
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

private final class StreamingDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (_ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(destination: URL,
         onProgress: @escaping @Sendable (_ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.continuation = cont
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
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

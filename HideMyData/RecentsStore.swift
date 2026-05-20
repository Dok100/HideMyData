import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
internal import UniformTypeIdentifiers

struct RecentItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: Kind
    let title: String
    let bookmarkData: Data
    let thumbnailFilename: String
    let addedAt: Date

    enum Kind: String, Codable {
        case pdf
        case image
    }
}

@Observable
@MainActor
final class RecentsStore {
    private(set) var items: [RecentItem] = []
    private(set) var isEnabled: Bool

    static let maxItems = 8
    private static let storageKey = "Inkognito.recents.v1"
    private static let legacyStorageKey = "HMD.recents.v1"
    private static let enabledKey = "Inkognito.recents.enabled"
    private static let legacyEnabledKey = "HMD.recents.enabled"

    init() {
        self.isEnabled =
            (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ??
            (UserDefaults.standard.object(forKey: Self.legacyEnabledKey) as? Bool) ??
            true
        load()
    }

    @discardableResult
    func add(url: URL, kind: RecentItem.Kind) -> Bool {
        guard isEnabled else { return false }
        guard let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope]) else { return false }

        let thumbnailFilename = "\(UUID().uuidString).png"
        let thumbnailURL = Self.thumbnailDirectory().appendingPathComponent(thumbnailFilename)
        guard generateThumbnail(for: url, kind: kind, destination: thumbnailURL) else { return false }

        removeExistingEntries(forResolvedPath: url.path)

        let item = RecentItem(
            id: UUID(),
            kind: kind,
            title: url.lastPathComponent,
            bookmarkData: bookmarkData,
            thumbnailFilename: thumbnailFilename,
            addedAt: Date()
        )

        items.insert(item, at: 0)
        trimToLimitIfNeeded()
        persist()
        return true
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
        deleteThumbnail(named: item.thumbnailFilename)
        persist()
    }

    func clearStoredItems() {
        clearAll()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyEnabledKey)

        if enabled {
            load()
        } else {
            clearAll()
        }
    }

    func resolve(_ item: RecentItem) -> (url: URL, didStartScope: Bool)? {
        guard let url = resolvedURL(from: item.bookmarkData) else { return nil }
        let startedScope = url.startAccessingSecurityScopedResource()
        return (url, startedScope)
    }

    func thumbnailURL(for item: RecentItem) -> URL {
        Self.thumbnailDirectory().appendingPathComponent(item.thumbnailFilename)
    }

    private func load() {
        guard isEnabled else {
            items = []
            return
        }

        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.legacyStorageKey),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            items = []
            return
        }

        let fileManager = FileManager.default
        items = decoded.filter { fileManager.fileExists(atPath: thumbnailURL(for: $0).path) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    private func clearAll() {
        for item in items {
            deleteThumbnail(named: item.thumbnailFilename)
        }
        items = []

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    private func removeExistingEntries(forResolvedPath path: String) {
        items.removeAll { item in
            guard let existingURL = resolvedURL(from: item.bookmarkData) else { return false }
            guard existingURL.path == path else { return false }
            deleteThumbnail(named: item.thumbnailFilename)
            return true
        }
    }

    private func trimToLimitIfNeeded() {
        guard items.count > Self.maxItems else { return }
        for staleItem in items.suffix(items.count - Self.maxItems) {
            deleteThumbnail(named: staleItem.thumbnailFilename)
        }
        items = Array(items.prefix(Self.maxItems))
    }

    private func resolvedURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &isStale
        )
    }

    private static func thumbnailDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateLegacyThumbsIfNeeded(base: applicationSupport)

        let directory = applicationSupport.appendingPathComponent("Inkognito/RecentsThumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func migrateLegacyThumbsIfNeeded(base: URL) {
        let fileManager = FileManager.default
        let legacyDirectory = base.appendingPathComponent("HideMyData/RecentsThumbs", isDirectory: true)
        let newParent = base.appendingPathComponent("Inkognito", isDirectory: true)
        let newDirectory = newParent.appendingPathComponent("RecentsThumbs", isDirectory: true)

        guard fileManager.fileExists(atPath: legacyDirectory.path),
              !fileManager.fileExists(atPath: newDirectory.path) else { return }

        try? fileManager.createDirectory(at: newParent, withIntermediateDirectories: true)
        try? fileManager.moveItem(at: legacyDirectory, to: newDirectory)
    }

    private func deleteThumbnail(named filename: String) {
        let fileURL = Self.thumbnailDirectory().appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func generateThumbnail(for url: URL, kind: RecentItem.Kind, destination: URL) -> Bool {
        switch kind {
        case .pdf:
            return generatePDFThumbnail(for: url, destination: destination)
        case .image:
            return generateImageThumbnail(for: url, destination: destination)
        }
    }

    private func generatePDFThumbnail(for url: URL, destination: URL) -> Bool {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else { return false }

        let pageBounds = page.bounds(for: .mediaBox)
        let maxDimension: CGFloat = 320
        let scale = maxDimension / max(pageBounds.width, pageBounds.height)
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)

        guard width > 0, height > 0 else { return false }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else { return false }
        return savePNG(image, to: destination)
    }

    private func generateImageThumbnail(for url: URL, destination: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }

        return savePNG(thumbnail, to: destination)
    }

    private func savePNG(_ image: CGImage, to destination: URL) -> Bool {
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }

        CGImageDestinationAddImage(imageDestination, image, nil)
        return CGImageDestinationFinalize(imageDestination)
    }
}

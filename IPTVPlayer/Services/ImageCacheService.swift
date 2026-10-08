import Foundation
@preconcurrency import AppKit

// MARK: - Image Cache Service

/// A simple in-memory + disk image cache for channel logos.
/// Prevents loading thousands of images simultaneously.
@MainActor
final class ImageCacheService: ObservableObject {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheDirectory: URL
    private let session: URLSession
    private var inFlightTasks: [String: Task<Data?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 500
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDirectory = cacheDir.appendingPathComponent("IPTVPlayer/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "IPTVSmartersPlayer"]
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Loads an image from cache or fetches it from the URL.
    func loadImage(from url: URL) async -> NSImage? {
        let key = cacheKey(for: url)

        // Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // Check for existing in-flight task
        if let existing = inFlightTasks[key] {
            if let data = await existing.value, let image = NSImage(data: data) {
                return image
            }
            return nil
        }

        let task = Task<Data?, Never> {
            await self.fetchImageData(from: url, key: key)
        }
        inFlightTasks[key] = task

        let data = await task.value
        inFlightTasks.removeValue(forKey: key)

        guard let data = data, let image = NSImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Clears the entire cache.
    func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheDirectory)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func fetchImageData(from url: URL, key: String) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Cache to disk
            saveToDisk(data: data, key: key)

            return data
        } catch {
            return nil
        }
    }

    private func cacheKey(for url: URL) -> String {
        let hash = url.absoluteString.data(using: .utf8)!
        var hashValue: UInt64 = 5381
        for byte in hash {
            hashValue = ((hashValue << 5) &+ hashValue) &+ UInt64(byte)
        }
        return String(hashValue)
    }

    private func diskPath(for key: String) -> URL {
        diskCacheDirectory.appendingPathComponent(key)
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let path = diskPath(for: key)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return NSImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        let path = diskPath(for: key)
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: path, options: .atomic)
        }
    }
}


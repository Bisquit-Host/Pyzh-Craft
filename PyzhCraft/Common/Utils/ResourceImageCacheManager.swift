import SwiftUI

/// Resource Image Cache Manager
/// Provides high-performance caching for resource list icons, supporting both memory and disk level caching
final class ResourceImageCacheManager: @unchecked Sendable {
    // MARK: - Singleton
    static let shared = ResourceImageCacheManager()
    // MARK: - Properties
    /// Image memory cache: key is URL string, value is NSImage
    private let imageCache: NSCache<NSString, NSImage>
    /// Shared URLSession, configure persistent cache strategy
    private let urlSession: URLSession
    // MARK: - Initialization
    private init() {
        // Configure memory cache: cache up to 100 images, total memory limit 20MB
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 20 * 1024 * 1024  // 20MB
        cache.name = "ResourceImageCache"
        self.imageCache = cache
        // Configure URLSession to use bulk disk cache
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024,  // 10MB memory cache
            diskCapacity: 100 * 1024 * 1024,   // 100MB disk cache
            diskPath: "ResourceImageCache"
        )
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }
    // MARK: - Public Methods
    /// Load images (use cache first)
    /// - Parameter url: Image URL
    /// - Returns: loaded image
    @MainActor
    func loadImage(from url: URL) async throws -> NSImage {
        let cacheKey = url.absoluteString as NSString
        // 1. Check the memory cache first
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        // 2. Load from the network (URLSession will automatically use disk cache)
        let (data, _) = try await urlSession.data(from: url)
        // 3. Parse the image
        guard let image = NSImage(data: data) else {
            throw NSError(
                domain: "ResourceImageCacheManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析图片数据"]
            )
        }
        // 4. Store in memory cache
        let cost = data.count
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }
    /// Preload image list (background batch loading)
    /// - Parameter urls: Image URL list
    func preloadImages(urls: [URL]) {
        Task.detached(priority: .utility) {
            for url in urls {
                let cacheKey = url.absoluteString as NSString
                // Skip cached images
                if self.imageCache.object(forKey: cacheKey) != nil {
                    continue
                }
                // Background loading
                do {
                    _ = try await self.loadImage(from: url)
                } catch {
                    // Silently handle preload failure
                    Logger.shared.debug("Failed to preload image: \(url.absoluteString)")
                }
            }
        }
    }
    /// Clean memory cache (keep disk cache)
    func clearMemoryCache() {
        imageCache.removeAllObjects()
    }
    /// Clean all caches (including disk cache)
    func clearAllCache() {
        imageCache.removeAllObjects()
        urlSession.configuration.urlCache?.removeAllCachedResponses()
    }
    /// Get cache statistics (for debugging)
    func getCacheInfo() -> (memoryCount: Int, diskSize: Int) {
        let diskSize = urlSession.configuration.urlCache?.currentDiskUsage ?? 0
        // NSCache does not provide the count attribute, which is estimated as used memory/average image size
        return (memoryCount: 0, diskSize: diskSize)
    }
}

/// Asynchronous image view with cache
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    // MARK: - Properties
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    private let cacheManager = ResourceImageCacheManager.shared
    // MARK: - Initialization
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    // MARK: - Body
    var body: some View {
        Group {
            if let image = image {
                content(Image(nsImage: image))
            } else if isLoading {
                placeholder()
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: url) { _, newUrl in
            if newUrl != url {
                loadImage()
            }
        }
    }
    // MARK: - Private Methods
    private func loadImage() {
        guard let url = url else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            do {
                let loadedImage = try await cacheManager.loadImage(from: url)
                if !Task.isCancelled {
                    self.image = loadedImage
                }
            } catch {
                // Handle errors silently, display placeholders
                if !Task.isCancelled {
                    self.image = nil
                }
            }
        }
    }
}

// MARK: - Convenience Initializers
extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Convenience initializer: default placeholder has gray background
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

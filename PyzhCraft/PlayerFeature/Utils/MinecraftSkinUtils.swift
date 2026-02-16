import SwiftUI
import CoreImage

// MARK: - Types and Constants

enum SkinType {
    case url, asset
}

// MARK: - Cache Wrapper
private class RenderedImageCache: NSObject {
    let headImage: CGImage  // Head image (8x8)
    let layerImage: CGImage // Layer image (8x8)
    let hasLayerContent: Bool  // Whether the layer has actual content (non-transparent pixels)
    let cost: Int  // Memory cost (number of bytes)

    init(headImage: CGImage, layerImage: CGImage, hasLayerContent: Bool) {
        self.headImage = headImage
        self.layerImage = layerImage
        self.hasLayerContent = hasLayerContent
        // Calculate memory cost: two 8x8 RGBA images = 2 * 8 * 8 * 4 = 512 bytes
        // Plus the overhead of CGImage objects, about 1KB each, for a total of about 2.5KB
        let headCost = Int(headImage.width * headImage.height * 4)
        let layerCost = Int(layerImage.width * layerImage.height * 4)
        self.cost = headCost + layerCost + 2 * 1024  // Two images + object overhead
        super.init()
    }
}

private enum Constants {
    static let padding: CGFloat = 6
    static let networkTimeout: TimeInterval = 10.0

    // Cache configuration - optimized configuration
    static let maxCacheSize = 100  // Cache up to 100 rendered images (previously 50 full images)
    static let maxCacheMemory = 2 * 1024 * 1024  // Cache up to 2MB of memory (~800 rendered images)

    // Minecraft skin coordinates (64x64 format)
    static let headStartX: CGFloat = 8
    static let headStartY: CGFloat = 8
    static let headWidth: CGFloat = 8
    static let headHeight: CGFloat = 8

    // Skin layer coordinates (64x64 format)
    static let layerStartX: CGFloat = 40
    static let layerStartY: CGFloat = 8
    static let layerWidth: CGFloat = 8
    static let layerHeight: CGFloat = 8
}

// MARK: - Main Component
struct MinecraftSkinUtils: View {
    let type: SkinType
    let src: String
    let size: CGFloat

    @State private var renderedCache: RenderedImageCache?
    @State private var error: String?
    @State private var isLoading: Bool = false
    @State private var loadTask: Task<Void, Never>?

    private static let imageCache: NSCache<NSString, RenderedImageCache> = {
        let cache = NSCache<NSString, RenderedImageCache>()
        cache.countLimit = Constants.maxCacheSize
        cache.totalCostLimit = Constants.maxCacheMemory
        // Set cache name for easy debugging
        cache.name = "MinecraftSkinCache"
        return cache
    }()

    // Shared URLSession to avoid creating a new session for each request
    private static let sharedURLSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.networkTimeout
        config.timeoutIntervalForResource = Constants.networkTimeout
        // Use caching policy: Allow local cache, but verify server responses
        config.requestCachePolicy = .returnCacheDataElseLoad
        // Reduce URLSession cache size, the application has a separate cache
        config.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,  // 2MB memory cache (reduced from 5MB)
            diskCapacity: 5 * 1024 * 1024,    // 5MB disk cache (reduced from 10MB)
            diskPath: "MinecraftSkinCache"
        )
        return URLSession(configuration: config)
    }()

    // Cache statistics (for debugging and monitoring)
    private static var cacheStats = CacheStats()

    // Only initialize once
    private static var memoryObserverSetup = false
    private static let memoryObserverQueue = DispatchQueue(label: "com.pyzhcraft.skincache.memory")

    private struct CacheStats {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0

        var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }
    }

    private static let ciContext: CIContext = {
        // Create CIContext with CPU-based rendering to avoid Metal shader cache conflicts
        // This is more appropriate for simple image cropping operations and prevents
        // Metal shader compilation lock file conflicts during development
        let options: [CIContextOption: Any] = [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false,
            .name: "MinecraftSkinProcessor",
        ]
        let context = CIContext(options: options)
        // Initialize cache maintenance tasks (only once)
        setupMemoryPressureObserverOnce()
        return context
    }()

    // Generate cache key
    private var cacheKey: String {
        let typeString: String
        switch type {
        case .url:
            typeString = "url"
        case .asset:
            typeString = "asset"
        }
        return "\(typeString):\(src)"
    }

    // Get cached rendered image
    private static func getCachedRenderedImage(for key: String) -> RenderedImageCache? {
        let nsKey = key as NSString
        if let cache = imageCache.object(forKey: nsKey) {
            cacheStats.hits += 1
            return cache
        } else {
            cacheStats.misses += 1
            return nil
        }
    }

    // Check if the image has non-transparent pixels
    private static func hasNonTransparentPixels(_ cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height

        // Create bitmap context to ensure consistent format (RGBA)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return false
        }

        // Draw an image into a bitmap context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check the alpha channel of each pixel (alpha is the 4th byte in RGBA format)
        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = (y * width + x) * bytesPerPixel
                let alpha = pixelData[pixelOffset + 3]
                if alpha > 0 {
                    return true  // Find non-transparent pixels
                }
            }
        }
        return false  // All pixels are transparent
    }

    // Render and cache the image (cropped CGImage)
    private static func renderAndCacheImage(_ ciImage: CIImage, for key: String, context: CIContext) -> RenderedImageCache? {
        let nsKey = key as NSString

        // Check if cached
        if let cached = imageCache.object(forKey: nsKey) {
            return cached
        }

        // Render head image
        let headRect = CGRect(
            x: Constants.headStartX,
            y: ciImage.extent.height - Constants.headStartY - Constants.headHeight,
            width: Constants.headWidth,
            height: Constants.headHeight
        )
        let headCropped = ciImage.cropped(to: headRect)

        // Render layer image
        let layerRect = CGRect(
            x: Constants.layerStartX,
            y: ciImage.extent.height - Constants.layerStartY - Constants.layerHeight,
            width: Constants.layerWidth,
            height: Constants.layerHeight
        )
        let layerCropped = ciImage.cropped(to: layerRect)

        // Convert to CGImage
        guard let headCGImage = context.createCGImage(headCropped, from: headCropped.extent),
              let layerCGImage = context.createCGImage(layerCropped, from: layerCropped.extent) else {
            return nil
        }

        // Check if the layer has actual content
        let hasLayerContent = hasNonTransparentPixels(layerCGImage)

        // Create cache object
        let cache = RenderedImageCache(headImage: headCGImage, layerImage: layerCGImage, hasLayerContent: hasLayerContent)
        imageCache.setObject(cache, forKey: nsKey, cost: cache.cost)
        return cache
    }

    // Clean cache (for use when memory pressure occurs)
    static func clearCache() {
        imageCache.removeAllObjects()
        cacheStats = CacheStats()
        Logger.shared.debug("🧹 MinecraftSkinUtils 缓存已清理")
    }

    // Get the current cache configuration (for debugging)
    static func getCacheInfo() -> (countLimit: Int, memoryLimit: Int, hitRate: Double) {
        return (
            countLimit: imageCache.countLimit,
            memoryLimit: imageCache.totalCostLimit,
            hitRate: cacheStats.hitRate
        )
    }

    // Get cache statistics (for debugging)
    static func getCacheStats() -> (hits: Int, misses: Int, hitRate: Double) {
        return (
            hits: cacheStats.hits,
            misses: cacheStats.misses,
            hitRate: cacheStats.hitRate
        )
    }

    // Initialize cache maintenance tasks (make sure to initialize only once)
    private static func setupMemoryPressureObserverOnce() {
        memoryObserverQueue.sync {
            guard !memoryObserverSetup else { return }
            memoryObserverSetup = true
        }
    }

    init(type: SkinType, src: String, size: CGFloat = 64) {
        self.type = type
        self.src = src
        self.size = size
    }

    var body: some View {
        ZStack {
            if let cache = renderedCache {
                avatarLayers(for: cache)
            } else if isLoading {
                // Loading indicator
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if error != nil {
                // Use default Steve skin when loading fails
                Self(type: .asset, src: "steve", size: size)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            // Check cache first
            if let cached = Self.getCachedRenderedImage(for: cacheKey) {
                self.renderedCache = cached
                self.isLoading = false
            } else {
                loadSkinData()
            }
        }
        .onChange(of: src) { _, _ in
            // When src changes, check the new cache key (cacheKey will be automatically calculated based on the new src)
            if let cached = Self.getCachedRenderedImage(for: cacheKey) {
                self.renderedCache = cached
                self.isLoading = false
                self.error = nil
            } else {
                self.renderedCache = nil
                self.error = nil
                loadSkinData()
            }
        }
        .onDisappear {
            // Cancel ongoing tasks to avoid memory leaks
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @ViewBuilder
    private func avatarLayers(for cache: RenderedImageCache) -> some View {
        ZStack {
            // Head layer - use cached CGImage directly without cropping and converting again
            // If there is no mask layer, use full size, otherwise use 0.9x size
            Image(decorative: cache.headImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .frame(
                    width: cache.hasLayerContent ? size * 0.9 : size,
                    height: cache.hasLayerContent ? size * 0.9 : size
                )
                .clipped()
            // Skin layer (overlay) - Use cached CGImage directly
            // Only shown if the layer has actual content
            if cache.hasLayerContent {
                Image(decorative: cache.layerImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .clipped()
            }
        }
        .shadow(color: Color.black.opacity(0.6), radius: 1)
    }

    private func loadSkinData() {
        error = nil
        isLoading = true

        // Cancel previous task
        loadTask?.cancel()

        loadTask = Task {
            do {
                // Check if the task has been canceled
                try Task.checkCancellation()

                Logger.shared.debug("Loading skin: \(src)")

                let data = try await loadData()

                try Task.checkCancellation()

                guard let ciImage = CIImage(data: data) else {
                    throw GlobalError.validation(i18nKey: "Invalid Image Data",
                        level: .silent
                    )
                }

                // Validate skin dimensions
                guard ciImage.extent.width == 64 && ciImage.extent.height == 64 else {
                    throw GlobalError.validation(i18nKey: "Unsupported Skin Format",
                        level: .silent
                    )
                }

                try Task.checkCancellation()

                // Render and cache the image (cropped CGImage)
                // Render on a background thread to avoid blocking the main thread
                let cacheKeyValue = cacheKey
                let renderedCache = await Task.detached {
                    await Self.renderAndCacheImage(ciImage, for: cacheKeyValue, context: Self.ciContext)
                }.value

                await MainActor.run {
                    self.renderedCache = renderedCache
                    self.isLoading = false
                }
            } catch is CancellationError {
                // The task was canceled and does not need to be processed
                await MainActor.run {
                    self.isLoading = false
                }
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URL request is canceled (usually the view is destroyed or recreated), handled silently
                await MainActor.run {
                    self.isLoading = false
                }
                return
            } catch {
                let globalError = GlobalError.from(error)
                await MainActor.run {
                    self.error = globalError.chineseMessage
                    self.isLoading = false
                }
                Logger.shared.error("❌ 皮肤加载失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
        }
    }

    private func loadData() async throws -> Data {
        switch type {
        case .asset:
            return try await loadAssetData()
        case .url:
            return try await loadURLData()
        }
    }

    private func loadAssetData() async throws -> Data {
        guard let image = NSImage(named: src),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw GlobalError.resource(i18nKey: "Asset Not Found",
                level: .silent
            )
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
            throw GlobalError.validation(i18nKey: "Invalid Image Data",
                level: .silent
            )
        }

        return data
    }

    private func loadURLData() async throws -> Data {
        guard let url = URL(string: src) else {
            throw GlobalError.validation(i18nKey: "Invalid URL",
                level: .silent
            )
        }

        // Use unified API client (needs to handle non-200 status codes)
        let request = URLRequest(url: url)
        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        switch httpResponse.statusCode {
        case 200:
            return data
        case 404:
            throw GlobalError(type: .resource, i18nKey: "Skin not found",
                level: .silent
            )
        case 408, 504:
            throw GlobalError.download(i18nKey: "Network Timeout",
                level: .silent
            )
        default:
            throw GlobalError.download(i18nKey: "Skin Download Failed",
                level: .silent
            )
        }
    }

    // MARK: - Export Functions

    /// Export player avatar image
    /// - Parameters:
    ///   - type: skin type (URL or Asset)
    ///   - src: skin source (URL or Asset name)
    ///   - size: export size (1024 or 2048)
    /// - Returns: Merged avatar image (head and layer overlap)
    static func exportAvatarImage(type: SkinType, src: String, size: Int) async throws -> NSImage {
        // Load skin data
        let data: Data
        switch type {
        case .asset:
            guard let image = NSImage(named: src),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw GlobalError.resource(i18nKey: "Asset Not Found",
                    level: .silent
                )
            }
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            guard let imageData = bitmapRep.representation(using: .png, properties: [:]) else {
                throw GlobalError.validation(i18nKey: "Invalid Image Data",
                    level: .silent
                )
            }
            data = imageData
        case .url:
            guard let url = URL(string: src) else {
                throw GlobalError.validation(i18nKey: "Invalid URL",
                    level: .silent
                )
            }
            let request = URLRequest(url: url)
            let (responseData, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

            guard httpResponse.statusCode == 200 else {
                throw GlobalError.download(i18nKey: "Skin Download Failed",
                    level: .silent
                )
            }
            data = responseData
        }

        // Create CIImage
        guard let ciImage = CIImage(data: data) else {
            throw GlobalError.validation(i18nKey: "Invalid Image Data",
                level: .silent
            )
        }

        // Verify skin size
        guard ciImage.extent.width == 64 && ciImage.extent.height == 64 else {
            throw GlobalError.validation(i18nKey: "Unsupported Skin Format",
                level: .silent
            )
        }

        // Crop header and layers
        let headRect = CGRect(
            x: Constants.headStartX,
            y: ciImage.extent.height - Constants.headStartY - Constants.headHeight,
            width: Constants.headWidth,
            height: Constants.headHeight
        )
        let headCropped = ciImage.cropped(to: headRect)

        let layerRect = CGRect(
            x: Constants.layerStartX,
            y: ciImage.extent.height - Constants.layerStartY - Constants.layerHeight,
            width: Constants.layerWidth,
            height: Constants.layerHeight
        )
        let layerCropped = ciImage.cropped(to: layerRect)

        // Convert to CGImage and zoom in
        guard let headCGImage = ciContext.createCGImage(headCropped, from: headCropped.extent),
              let layerCGImage = ciContext.createCGImage(layerCropped, from: layerCropped.extent) else {
            throw GlobalError(type: .validation, i18nKey: "Image processing failed",
                level: .silent
            )
        }

        // Check if the layer has content
        let hasLayerContent = hasNonTransparentPixels(layerCGImage)

        // Create image of target size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size
        let bitsPerComponent = 8

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GlobalError(type: .validation, i18nKey: "Image context failed",
                level: .silent
            )
        }

        // Draw the head layer (zoom out to 90% if you need to scale to fit the layer)
        let headSize = hasLayerContent ? Int(Double(size) * 0.9) : size
        let headOffset = hasLayerContent ? (size - headSize) / 2 : 0
        context.interpolationQuality = .none
        context.draw(headCGImage, in: CGRect(x: headOffset, y: headOffset, width: headSize, height: headSize))

        // If there is layer content, draw the layer (overlaying it above the head)
        if hasLayerContent {
            context.draw(layerCGImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        }

        // Get the final CGImage
        guard let finalCGImage = context.makeImage() else {
            throw GlobalError(type: .validation, i18nKey: "Final image failed",
                level: .silent
            )
        }

        // Convert to NSImage
        return NSImage(cgImage: finalCGImage, size: NSSize(width: size, height: size))
    }
}

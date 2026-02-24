import Kingfisher
import SwiftUI

/// Resource Image Cache Manager
/// Uses Kingfisher for memory and disk caching
final class ResourceImageCacheManager: @unchecked Sendable {
    static let shared = ResourceImageCacheManager()
    
    private init() {}
    
    @MainActor
    func loadImage(from url: URL) async throws -> NSImage {
        let result = try await KingfisherManager.shared.retrieveImage(with: url)
        return result.image
    }
    
    func preloadImages(urls: [URL]) {
        let prefetcher = ImagePrefetcher(urls: urls)
        prefetcher.start()
    }
    
    @MainActor
    func clearMemoryCache() {
        ImageCache.default.clearMemoryCache()
    }
    
    func clearAllCache() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
    }
    
    func getCacheInfo() async -> (memoryCount: Int, diskSize: Int) {
        let diskSize = await withCheckedContinuation { continuation in
            ImageCache.default.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    continuation.resume(returning: size)
                case .failure:
                    continuation.resume(returning: 0)
                }
            }
        }
        return (memoryCount: 0, diskSize: Int(diskSize))
    }
}

/// Asynchronous image view with cache
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: NSImage?
    @State private var loadTask: Task<Void, Never>?
    private let cacheManager = ResourceImageCacheManager.shared
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
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
        .onChange(of: url) {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url else {
            image = nil
            return
        }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            do {
                let loadedImage = try await cacheManager.loadImage(from: url)
                if !Task.isCancelled {
                    image = loadedImage
                }
            } catch {
                if !Task.isCancelled {
                    image = nil
                }
            }
        }
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

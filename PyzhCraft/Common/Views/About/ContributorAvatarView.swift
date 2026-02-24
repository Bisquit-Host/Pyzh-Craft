import SwiftUI

/// Contributor avatar image cache manager
/// Use NSCache to limit memory usage and avoid memory overflow caused by loading too many images
final class ContributorAvatarCache: @unchecked Sendable {
    static let shared = ContributorAvatarCache()

    /// Image cache: key is URL string, value is NSImage
    private let imageCache: NSCache<NSString, NSImage>

    /// Shared URLSession, enable caching to reduce memory footprint
    private let urlSession: URLSession

    private init() {
        // Set cache limit: cache up to 30 images, total memory limit 3MB
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 30
        cache.totalCostLimit = 3 * 1024 * 1024  // 3MB
        cache.name = "ContributorAvatarCache"
        self.imageCache = cache

        // Configure URLSession to use a smaller cache
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 1 * 1024 * 1024,  // 1MB memory cache
            diskCapacity: 5 * 1024 * 1024,    // 5MB disk cache
            diskPath: "ContributorAvatarCache"
        )
        self.urlSession = URLSession(configuration: config)
    }

    /// Load images
    @MainActor
    func loadImage(from url: URL) async throws -> NSImage {
        let cacheKey = url.absoluteString as NSString

        // Check cache first
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        // Load from network
        let (data, _) = try await urlSession.data(from: url)
        guard let image = NSImage(data: data) else {
            throw NSError(domain: "ContributorAvatarCache", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析图片数据"])
        }

        // Calculate image size (for caching costs)
        let cost = data.count
        imageCache.setObject(image, forKey: cacheKey, cost: cost)

        return image
    }

    /// clear cache
    func clearCache() {
        imageCache.removeAllObjects()
    }
}

/// Contributor avatar view
struct ContributorAvatarView: View {
    let avatarUrl: String
    let size: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    init(avatarUrl: String, size: CGFloat = 32) {
        self.avatarUrl = avatarUrl
        self.size = size
    }

    /// Get the optimized avatar URL (using GitHub's thumbnail parameter)
    /// GitHub supports the ?s=size parameter to obtain images of a specified size to reduce download size
    private var optimizedAvatarURL: URL? {
        guard let url = URL(string: avatarUrl.httpToHttps()) else { return nil }

        // If it is already a GitHub avatar URL, add the size parameter
        // GitHub avatar URL format: https://avatars.githubusercontent.com/u/xxx or https://github.com/identicons/xxx.png
        if url.host?.contains("github.com") == true || url.host?.contains("avatars.githubusercontent.com") == true {
            // Calculate required pixel size (@2x screen requires 2x)
            let pixelSize = Int(size * 2)
            // Remove existing query parameters (if any)
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "s", value: "\(pixelSize)")]
            return components?.url
        }

        return url
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .foregroundColor(.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            } else {
                Rectangle()
                    .foregroundColor(.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .font(.caption)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .onAppear {
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadImage() {
        guard let url = optimizedAvatarURL else { return }

        loadTask?.cancel()
        loadTask = Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                let loadedImage = try await ContributorAvatarCache.shared.loadImage(from: url)
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

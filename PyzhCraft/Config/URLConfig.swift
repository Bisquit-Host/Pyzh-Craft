import Foundation

enum URLConfig {
    /// An auxiliary method for safely creating URLs. When invalid, logs are logged and return placeholder URLs to avoid crashes in the production environment
    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            Logger.shared.error("Invalid URL: \(string)，使用占位 URL")
            // Use guard let to avoid forced unwrapping
            guard let fallbackURL = URL(string: "https://localhost") else {
                // If even localhost fails, a hardcoded URL is returned (this should not happen in theory)
                return URL(string: "https://localhost") ?? URL(fileURLWithPath: "/")
            }
            return fallbackURL
        }
        return url
    }

    /// GitHub proxy settings (read from UserDefaults, avoid UI dependencies)
    private enum GitHubProxySettings {
        static let defaultProxy = "https://gh-proxy.com"
        static let enableKey = "enableGitHubProxy"
        static let urlKey = "gitProxyURL"

        static var isEnabled: Bool {
            let defaults = UserDefaults.standard
            // Enabled by default when not written
            return (defaults.object(forKey: enableKey) as? Bool) ?? true
        }

        static var proxyString: String {
            let defaults = UserDefaults.standard
            return (defaults.string(forKey: urlKey) ?? defaultProxy)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Returns the proxy prefix used for splicing (guaranteed to be http(s) and not ending with /), or nil if invalid
        static var normalizedProxyPrefix: String? {
            let proxy = proxyString
            guard !proxy.isEmpty else { return nil }
            guard let url = URL(string: proxy), let scheme = url.scheme else { return nil }
            guard scheme == "http" || scheme == "https" else { return nil }
            return proxy.hasSuffix("/") ? String(proxy.dropLast()) : proxy
        }
    }

    // Constant string to avoid repeated creation
    private static let githubHost = "github.com"
    private static let rawGithubHost = "raw.githubusercontent.com"

    // Public method: Apply proxy for GitHub URL (if needed)
    /// Apply gitProxyURL proxy for GitHub related URLs
    /// - Parameter url: original URL
    /// - Returns: URL after applying proxy (if required)
    static func applyGitProxyIfNeeded(_ url: URL) -> URL {
        guard GitHubProxySettings.isEnabled else { return url }
        guard let proxy = GitHubProxySettings.normalizedProxyPrefix else { return url }

        // Optimization: Use the host attribute of URL directly to avoid conversion to String
        guard let host = url.host else { return url }

        // Apply proxy only to GitHub related domains (excluding api.github.com)
        let isGitHubURL = host == githubHost || host == rawGithubHost
        guard isGitHubURL else { return url }

        // Optimization: Use URL's absoluteString to check if there is already a proxy prefix
        let urlString = url.absoluteString
        if urlString.hasPrefix("\(proxy)/") { return url }

        // Use string interpolation instead of string concatenation
        let proxiedString = "\(proxy)/\(urlString)"
        return Self.url(proxiedString)
    }

    // Public method: Apply proxy for GitHub URL string (if needed)
    /// Apply the gitProxyURL proxy to GitHub-related URL strings
    /// - Parameter urlString: original URL string
    /// - Returns: URL string after applying proxy (if required)
    /// Optimization: Use autoreleasepool to release temporary URL objects in time
    static func applyGitProxyIfNeeded(_ urlString: String) -> String {
        return autoreleasepool {
            guard let url = URL(string: urlString) else { return urlString }
            return applyGitProxyIfNeeded(url).absoluteString
        }
    }

    // API endpoint
    enum API {
        // Authentication API
        enum Authentication {
            // Microsoft OAuth live.com endpoints for official launcher-style device code flow
            static let deviceCode = URLConfig.url("https://login.live.com/oauth20_connect.srf")
            static let token = URLConfig.url("https://login.live.com/oauth20_token.srf")

            // Xbox Live
            static let xboxLiveAuth = URLConfig.url("https://user.auth.xboxlive.com/user/authenticate")
            static let xstsAuth = URLConfig.url("https://xsts.auth.xboxlive.com/xsts/authorize")

            // Minecraft Services
            static let minecraftLogin = URLConfig.url("https://api.minecraftservices.com/authentication/login_with_xbox")
            static let minecraftProfile = URLConfig.url("https://api.minecraftservices.com/minecraft/profile")
            static let minecraftEntitlements = URLConfig.url("https://api.minecraftservices.com/entitlements/mcstore")
            // Player skin / cape operations
            static let minecraftProfileSkins = URLConfig.url("https://api.minecraftservices.com/minecraft/profile/skins")
            static let minecraftProfileActiveSkin = URLConfig.url("https://api.minecraftservices.com/minecraft/profile/skins/active")
            static let minecraftProfileActiveCape = URLConfig.url("https://api.minecraftservices.com/minecraft/profile/capes/active")
        }

        // Minecraft API
        enum Minecraft {
            static let versionList = URLConfig.url("https://launchermeta.mojang.com/mc/game/version_manifest.json")
        }

        // Java Runtime API
        enum JavaRuntime {
            static let baseURL = URLConfig.url("https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871")
            static let allRuntimes = baseURL.appendingPathComponent("all.json")

            /// Get Java runtime manifest
            /// - Parameter manifestURL: Manifest URL
            /// - Returns: Listing URL
            static func manifest(_ manifestURL: String) -> URL {
                URLConfig.url(manifestURL)
            }
        }

        // Zulu JDK download URL for the ARM platform-specific version
        enum JavaRuntimeARM {
            static let jreLegacy = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jre8.0.462-macosx_aarch64.zip")
            static let javaRuntimeAlpha = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu16.32.15-ca-jre16.0.2-macosx_aarch64.zip")
            static let javaRuntimeBeta = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jre17.0.16-macosx_aarch64.zip")
        }

        // Intel platform-specific version of Zulu JDK download URL
        enum JavaRuntimeIntel {
            static let jreLegacy = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jre8.0.462-macosx_x64.zip")
            static let javaRuntimeAlpha = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu16.32.15-ca-jre16.0.2-macosx_x64.zip")
            static let javaRuntimeBeta = URLConfig.url("https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jre17.0.16-macosx_x64.zip")
        }

        // GitHub API
        enum GitHub {
            static let gitHubBase = URLConfig.url("https://github.com")
            static let baseURL = URLConfig.url("https://api.github.com")
            static let repositoryOwner = "suhang12332"
            static let assetsRepositoryName = "Swift-Craft-Launcher-Assets"
            static let repositoryName = "Swift-Craft-Launcher"
            /// Announcement base address:
            /// For example: https://raw.githubusercontent.com/suhang12332/Swift-Craft-Launcher-Assets/refs/heads/main/news/api/announcements/0.3.1-beta/ar.json
            static let announcementBaseURL = URLConfig.url("https://raw.githubusercontent.com/\(repositoryOwner)/\(assetsRepositoryName)/refs/heads/main/news/api/announcements")

            // Private method: Build the base path of the warehouse
            private static var repositoryBaseURL: URL {
                baseURL
                    .appendingPathComponent("repos")
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(repositoryName)
            }

            static func latestRelease() -> URL {
                URLConfig.applyGitProxyIfNeeded(
                    repositoryBaseURL.appendingPathComponent("releases/latest")
                )
            }

            static func contributors(perPage: Int = 50) -> URL {
                let url = repositoryBaseURL
                    .appendingPathComponent("contributors")
                    .appending(queryItems: [
                        URLQueryItem(name: "per_page", value: "\(perPage)")
                    ])
                return URLConfig.applyGitProxyIfNeeded(url)
            }

            // GitHub repository homepage URL
            static func repositoryURL() -> URL {
                return gitHubBase
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(repositoryName)
            }

            // Appcast related
            static func appcastURL(
                architecture: String
            ) -> URL {
                let appcastFileName = "appcast-\(architecture).xml"
                let url = gitHubBase
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(repositoryName)
                    .appendingPathComponent("releases")
                    .appendingPathComponent("latest")
                    .appendingPathComponent("download")
                    .appendingPathComponent(appcastFileName)
                return URLConfig.applyGitProxyIfNeeded(url)
            }

            // Static contributor data
            static func staticContributors() -> URL {
                let timestamp = Int(Date().timeIntervalSince1970)
                let url = URLConfig.url("https://raw.githubusercontent.com")
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(assetsRepositoryName)
                    .appendingPathComponent("refs")
                    .appendingPathComponent("heads")
                    .appendingPathComponent("main")
                    .appendingPathComponent("contributors")
                    .appendingPathComponent("contributors.json")
                    .appending(queryItems: [
                        URLQueryItem(name: "timestamp", value: "\(timestamp)")
                    ])
                return URLConfig.applyGitProxyIfNeeded(url)
            }

            // Acknowledgments data
            static func acknowledgements() -> URL {
                let timestamp = Int(Date().timeIntervalSince1970)
                let url = URLConfig.url("https://raw.githubusercontent.com")
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(assetsRepositoryName)
                    .appendingPathComponent("refs")
                    .appendingPathComponent("heads")
                    .appendingPathComponent("main")
                    .appendingPathComponent("contributors")
                    .appendingPathComponent("acknowledgements.json")
                    .appending(queryItems: [
                        URLQueryItem(name: "timestamp", value: "\(timestamp)")
                    ])
                return URLConfig.applyGitProxyIfNeeded(url)
            }

            // LICENSE file (API)
            static func license(ref: String = "main") -> URL {
                let url = repositoryBaseURL
                    .appendingPathComponent("contents")
                    .appendingPathComponent("LICENSE")
                    .appending(queryItems: [
                        URLQueryItem(name: "ref", value: ref)
                    ])
                return URLConfig.applyGitProxyIfNeeded(url)
            }

            // LICENSE file (web page)
            static func licenseWebPage(ref: String = "main") -> URL {
                let url = gitHubBase
                    .appendingPathComponent(repositoryOwner)
                    .appendingPathComponent(repositoryName)
                    .appendingPathComponent("blob")
                    .appendingPathComponent(ref)
                    .appendingPathComponent("LICENSE")
                // The License webpage does not go through the GitHub proxy and directly opens the original github.com link
                return url
            }

            // Announcement API
            /// Get announcement URL
            /// - Parameters:
            ///   - version: application version number
            ///   - language: language code, such as "zh-Hans"
            /// - Returns: Announcement URL (with timestamp to avoid caching)
            static func announcement(version: String, language: String) -> URL {
                let timestamp = Int(Date().timeIntervalSince1970)
                let url = announcementBaseURL
                    .appendingPathComponent(version)
                    .appendingPathComponent("\(language).json")
                    .appending(queryItems: [
                        URLQueryItem(name: "timestamp", value: "\(timestamp)")
                    ])
                return URLConfig.applyGitProxyIfNeeded(url)
            }
        }

        // Modrinth API
        enum Modrinth {
            static let baseURL = URLConfig.url("https://api.modrinth.com/v2")
            /// Modrinth project details base URL, for example: https://modrinth.com/mod/fabric-api
            static let webProjectBase = "https://modrinth.com/mod/"

            // Project related
            static func project(id: String) -> URL {
                baseURL.appendingPathComponent("project/\(id)")
            }

            // Version related
            static func version(id: String) -> URL {
                baseURL.appendingPathComponent("project/\(id)/version")
            }

            static func versionId(versionId: String) -> URL {
                baseURL.appendingPathComponent("version/\(versionId)")
            }

            // Search related
            static var search: URL {
                baseURL.appendingPathComponent("search")
            }

            static func versionFile(hash: String) -> URL {
                baseURL.appendingPathComponent("version_file/\(hash)")
            }

            // tag related
            static var gameVersionTag: URL {
                baseURL.appendingPathComponent("tag/game_version")
            }

            static var loaderTag: URL {
                baseURL.appendingPathComponent("tag/loader")
            }

            static var categoryTag: URL {
                baseURL.appendingPathComponent("tag/category")
            }

            // Loader API
            static func loaderManifest(loader: String) -> URL {
                URLConfig.url("https://launcher-meta.modrinth.com/\(loader)/v0/manifest.json")
            }

            // Minecraft Version API
            static func versionInfo(version: String) -> URL {
                URLConfig.url("https://launcher-meta.modrinth.com/minecraft/v0/versions/\(version).json")
            }

            static let maven = URLConfig.url("https://launcher-meta.modrinth.com/maven/")

            static func loaderProfile(loader: String, version: String) -> URL {
                URLConfig.url("https://launcher-meta.modrinth.com/\(loader)/v0/versions/\(version).json")
            }

            // Download URL
            /// Generate Modrinth file download URL
            /// - Parameters:
            ///   - projectId: project ID
            ///   - versionId: version ID
            ///   - fileName: file name (URL encoding will be performed automatically)
            /// - Returns: Download URL
            static func downloadUrl(projectId: String, versionId: String, fileName: String) -> String {
                let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
                return "https://cdn.modrinth.com/data/\(projectId)/versions/\(versionId)/\(encodedFileName)"
            }
        }
        // FabricMC API
        enum Fabric {
            static let loader = URLConfig.url("https://meta.fabricmc.net/v2/versions/loader")
        }

        // Quilt API
        enum Quilt {
            static let loaderBase = URLConfig.url("https://meta.quiltmc.org/v3/versions/loader/")
        }

        // CurseForge API
        enum CurseForge {
            static let mirrorBaseURL = URLConfig.url("https://api.curseforge.com/v1")
            static let fallbackDownloadBaseURL = URLConfig.url("https://edge.forgecdn.net/files")
            /// CurseForge project details base URL, for example: https://www.curseforge.com/minecraft/mc-mods/geckolib
            static let webProjectBase = "https://www.curseforge.com/minecraft/mc-mods/"

            static func fileDetail(projectId: Int, fileId: Int) -> URL {
                mirrorBaseURL.appendingPathComponent("mods/\(projectId)/files/\(fileId)")
            }

            static func modDetail(modId: Int) -> URL {
                mirrorBaseURL.appendingPathComponent("mods/\(modId)")
            }

            static func modDescription(modId: Int) -> URL {
                mirrorBaseURL.appendingPathComponent("mods/\(modId)/description")
            }

            static func fallbackDownloadUrl(fileId: Int, fileName: String) -> URL {
                // Format: https://edge.forgecdn.net/files/{first three digits of fileId}/{last three digits of fileId}/{fileName}
                fallbackDownloadBaseURL
                    .appendingPathComponent("\(fileId / 1000)")
                    .appendingPathComponent("\(fileId % 1000)")
                    .appendingPathComponent(fileName)
            }

            static func projectFiles(projectId: Int, gameVersion: String? = nil, modLoaderType: Int? = nil) -> URL {
                let url = mirrorBaseURL.appendingPathComponent("mods/\(projectId)/files")

                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var queryItems: [URLQueryItem] = []

                if let gameVersion = gameVersion {
                    queryItems.append(URLQueryItem(name: "gameVersion", value: gameVersion))
                }

                if let modLoaderType = modLoaderType {
                    queryItems.append(URLQueryItem(name: "modLoaderType", value: String(modLoaderType)))
                }

                if !queryItems.isEmpty {
                    components?.queryItems = queryItems
                }

                return components?.url ?? url
            }

            // Search related
            static var search: URL {
                mirrorBaseURL.appendingPathComponent("mods/search")
            }

            // Classification related
            static var categories: URL {
                mirrorBaseURL.appendingPathComponent("categories")
            }

            // Game version related
            static var gameVersions: URL {
                mirrorBaseURL.appendingPathComponent("minecraft/version")
            }
        }

        // IP Location API
        enum IPLocation {
            static var currentLocation: URL {
                // Use ipapi.co's free API, support HTTPS, return country code
                URLConfig.url("https://ipapi.co/json/")
            }
        }
    }

    // Store URLs
    enum Store {
        // Minecraft purchase link
        static let minecraftPurchase = URLConfig.url("https://www.xbox.com/zh-CN/games/store/productId/9NXP44L49SHJ")
    }
}

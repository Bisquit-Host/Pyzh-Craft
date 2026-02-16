import Foundation
import CommonCrypto

enum DownloadManager {
    enum ResourceType: String {
        case mod, datapack, shader, resourcepack

        var folderName: String {
            switch self {
            case .mod: AppConstants.DirectoryNames.mods
            case .datapack: AppConstants.DirectoryNames.datapacks
            case .shader: AppConstants.DirectoryNames.shaderpacks
            case .resourcepack: AppConstants.DirectoryNames.resourcepacks
            }
        }

        init?(from string: String) {
            // Optimization: Use caseInsensitiveCompare to avoid creating temporary lowercase strings
            let lowercased = string.lowercased()
            switch lowercased {
            case "mod": self = .mod
            case "datapack": self = .datapack
            case "shader": self = .shader
            case "resourcepack": self = .resourcepack
            default: return nil
            }
        }
    }

    /// Download resource file
    /// - Parameters:
    ///   - game: game information
    ///   - urlString: download address
    ///   - resourceType: resource type (such as "mod", "datapack", "shader", "resourcepack")
    ///   - expectedSha1: expected SHA1 value
    /// - Returns: Downloaded local file URL
    /// - Throws: GlobalError when the operation fails
    static func downloadResource(for game: GameVersionInfo, urlString: String, resourceType: String, expectedSha1: String? = nil) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                i18nKey: "Invalid Download URL",
                level: .notification
            )
        }

        guard let type = ResourceType(from: resourceType) else {
            throw GlobalError(type: .resource, i18nKey: "Unknown resource type",
                level: .notification
            )
        }

        let resourceDir: URL? = {
            switch type {
            case .mod:
                return AppPaths.modsDirectory(gameName: game.gameName)
            case .datapack:
                // Optimization: cache lowercase path components to avoid repeated creation
                let lowercasedPath = url.lastPathComponent.lowercased()
                if lowercasedPath.hasSuffix(".\(AppConstants.FileExtensions.jar)") {
                    return AppPaths.modsDirectory(gameName: game.gameName)
                }
                return AppPaths.datapacksDirectory(gameName: game.gameName)
            case .shader:
                return AppPaths.shaderpacksDirectory(gameName: game.gameName)
            case .resourcepack:
                // Optimization: cache lowercase path components to avoid repeated creation
                let lowercasedPath = url.lastPathComponent.lowercased()
                if lowercasedPath.hasSuffix(".\(AppConstants.FileExtensions.jar)") {
                    return AppPaths.modsDirectory(gameName: game.gameName)
                }
                return AppPaths.resourcepacksDirectory(gameName: game.gameName)
            }
        }()

        guard let resourceDirUnwrapped = resourceDir else {
            throw GlobalError.resource(
                i18nKey: "Directory Not Found",
                level: .notification
            )
        }

        let destURL = resourceDirUnwrapped.appendingPathComponent(url.lastPathComponent)
        // Optimization: Pass the created URL directly to avoid repeated creation in downloadFile
        return try await downloadFile(url: url, destinationURL: destURL, expectedSha1: expectedSha1)
    }

    // Constant string to avoid repeated creation
    private static let githubPrefix = "https://github.com/"
    private static let rawGithubPrefix = "https://raw.githubusercontent.com/"
    private static let githubHost = "github.com"
    private static let rawGithubHost = "raw.githubusercontent.com"

    /// Universally download files to the specified path (without splicing any directory structure)
    /// - Parameters:
    ///   - urlString: download address (string form)
    ///   - destinationURL: destination file path
    ///   - expectedSha1: expected SHA1 value
    /// - Returns: Downloaded local file URL
    /// - Throws: GlobalError when the operation fails
    static func downloadFile(
        urlString: String,
        destinationURL: URL,
        expectedSha1: String? = nil
    ) async throws -> URL {
        // Optimization: Create URL first, then call internal method
        let url: URL = try autoreleasepool {
            guard let url = URL(string: urlString) else {
                throw GlobalError.validation(
                    i18nKey: "Invalid Download URL",
                    level: .notification
                )
            }
            return url
        }
        return try await downloadFile(url: url, destinationURL: destinationURL, expectedSha1: expectedSha1)
    }

    /// Universal download file to specified path (internal method, accepts URL object)
    /// - Parameters:
    ///   - url: download address (URL object)
    ///   - destinationURL: destination file path
    ///   - expectedSha1: expected SHA1 value
    /// - Returns: Downloaded local file URL
    /// - Throws: GlobalError when the operation fails
    private static func downloadFile(
        url: URL,
        destinationURL: URL,
        expectedSha1: String? = nil
    ) async throws -> URL {
        // Optimization: Use autoreleasepool in the synchronization part to release temporary objects in time
        // Optimization: Use URL directly to avoid storing String and URL at the same time (save memory)
        let finalURL: URL = autoreleasepool {
            // Optimization: Directly use the host attribute check of the URL to avoid conversion to String
            let needsProxy: Bool
            if let host = url.host {
                needsProxy = host == githubHost || host == rawGithubHost
            } else {
                // If there is no host, check absoluteString (possibly a relative path)
                let absoluteString = url.absoluteString
                needsProxy = absoluteString.hasPrefix(githubPrefix) || absoluteString.hasPrefix(rawGithubPrefix)
            }

            if needsProxy {
                return URLConfig.applyGitProxyIfNeeded(url)
            } else {
                return url
            }
        }

        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw GlobalError.fileSystem(
                i18nKey: "Download Directory Creation Failed",
                level: .notification
            )
        }

        // Check if SHA1 verification is required
        let shouldCheckSha1 = (expectedSha1?.isEmpty == false)

        // if the file already exists
        let destinationPath = destinationURL.path
        if fileManager.fileExists(atPath: destinationPath) {
            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                // Optimization: Use autoreleasepool to release temporary objects during SHA1 calculation
                do {
                    let actualSha1 = try autoreleasepool {
                        try calculateFileSHA1(at: destinationURL)
                    }
                    if actualSha1 == expectedSha1 {
                        return destinationURL
                    }
                    // If the verification fails, continue downloading (without returning, continue executing the download logic below)
                } catch {
                    // If there is an error in the verification, continue downloading (without interruption)
                }
            } else {
                // Skip directly if there is no SHA1
                return destinationURL
            }
        }

        // Download files to a temporary location (asynchronous operation outside autoreleasepool)
        do {
            let (tempFileURL, response) = try await URLSession.shared.download(from: finalURL)
            defer {
                // Make sure temporary files are cleaned up
                try? fileManager.removeItem(at: tempFileURL)
            }

            // Optimization: Check status codes directly and reduce intermediate variables
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GlobalError.download(
                    i18nKey: "HTTP Status Error",
                    level: .notification
                )
            }

            // SHA1 verification (optimized: use autoreleasepool)
            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                try autoreleasepool {
                    let actualSha1 = try calculateFileSHA1(at: tempFileURL)
                    if actualSha1 != expectedSha1 {
                        throw GlobalError.validation(
                            i18nKey: "SHA1 Check Failed",
                            level: .notification
                        )
                    }
                }
            }

            // Move atomically to final position
            if fileManager.fileExists(atPath: destinationURL.path) {
                // Try to replace directly
                try fileManager.replaceItem(at: destinationURL, withItemAt: tempFileURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try fileManager.moveItem(at: tempFileURL, to: destinationURL)
            }

            return destinationURL
        } catch {
            // Convert error to GlobalError
            if let globalError = error as? GlobalError {
                throw globalError
            } else if error is URLError {
                throw GlobalError.download(
                    i18nKey: "Network Request Failed",
                    level: .notification
                )
            } else {
                throw GlobalError.download(
                    i18nKey: "General Failure",
                    level: .notification
                )
            }
        }
    }

    /// Calculate the SHA1 hash of a file
    /// - Parameter url: file path
    /// - Returns: SHA1 hash string
    /// - Throws: GlobalError when the operation fails
    static func calculateFileSHA1(at url: URL) throws -> String {
        try SHA1Calculator.sha1(ofFileAt: url)
    }
}

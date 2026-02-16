import Foundation

// Cache information structure
struct CacheInfo: Equatable {
    let fileCount: Int
    let totalSize: Int64 // byte
    let formattedSize: String

    init(fileCount: Int, totalSize: Int64) {
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.formattedSize = Self.formatFileSize(totalSize)
    }

    static func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// cache calculator
class CacheCalculator {
    static let shared = CacheCalculator()

    private init() {}

    /// Calculate game resource cache information
    /// - Throws: GlobalError when the operation fails
    func calculateMetaCacheInfo() throws -> CacheInfo {
        let resourceTypes = AppConstants.cacheResourceTypes
        var totalFileCount = 0
        var totalSize: Int64 = 0

        for type in resourceTypes {
            let typeDir = AppPaths.metaDirectory.appendingPathComponent(type)
            let (fileCount, size) = try calculateDirectorySize(typeDir)
            totalFileCount += fileCount
            totalSize += size
        }

        return CacheInfo(fileCount: totalFileCount, totalSize: totalSize)
    }

    /// Calculate application cache information
    /// - Throws: GlobalError when the operation fails
    func calculateCacheInfo() throws -> CacheInfo {
        let (fileCount, size) = try calculateDirectorySize(AppPaths.appCache)
        return CacheInfo(fileCount: fileCount, totalSize: size)
    }

    /// Calculate directory size
    /// - Parameter directory: directory path
    /// - Returns: (number of files, total size)
    /// - Throws: GlobalError when the operation fails
    private func calculateDirectorySize(_ directory: URL) throws -> (fileCount: Int, size: Int64) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return (0, 0)
        }

        var fileCount = 0
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            throw GlobalError.fileSystem(i18nKey: "Directory Enumeration Failed",
                level: .silent
            )
        }

        for case let fileURL as URL in enumerator {
            // Exclude .DS_Store files
            if fileURL.lastPathComponent == ".DS_Store" {
                continue
            }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    fileCount += 1
                    totalSize += Int64(fileSize)
                }
            } catch {
                Logger.shared.warning("无法获取文件大小: \(fileURL.path), 错误: \(error.localizedDescription)")
                // Continue processing other files without interrupting the entire calculation process
            }
        }

        return (fileCount, totalSize)
    }

    /// Calculate the cache information under the specified game profile
    /// - Parameter gameName: game name
    /// - Returns: cache information
    /// - Throws: GlobalError when the operation fails
    func calculateProfileCacheInfo(gameName: String) throws -> CacheInfo {

        let subdirectories = AppPaths.profileSubdirectories
        var totalFileCount = 0
        var totalSize: Int64 = 0

        for subdir in subdirectories {
            let subdirPath = AppPaths.profileDirectory(gameName: gameName).appendingPathComponent(subdir)
            let (fileCount, size) = try calculateDirectorySize(subdirPath)
            totalFileCount += fileCount
            totalSize += size
        }

        return CacheInfo(fileCount: totalFileCount, totalSize: totalSize)
    }
}

import Foundation
import ZIPFoundation

/// Integrated package packager
/// Responsible for packaging the temporary directory into a .mrpack file
enum ModPackArchiver {
    /// Packaging integration package
    /// - Parameters:
    ///   - tempDir: temporary directory (contains modrinth.index.json and overrides)
    ///   - outputPath: output file path
    static func archive(
        tempDir: URL,
        outputPath: URL
    ) throws {
        // If the output file already exists, delete it first
        if FileManager.default.fileExists(atPath: outputPath.path) {
            try FileManager.default.removeItem(at: outputPath)
        }

        // Create ZIP archive
        let archive: Archive
        do {
            archive = try Archive(url: outputPath, accessMode: .create)
        } catch {
            throw GlobalError.fileSystem(i18nKey: "Failed to create archive file",
                level: .notification
            )
        }

        // Add modrinth.index.json to the zip root directory
        let indexPath = tempDir.appendingPathComponent(AppConstants.modrinthIndexFileName)
        if FileManager.default.fileExists(atPath: indexPath.path) {
            let indexData = try Data(contentsOf: indexPath)
            try archive.addEntry(
                with: AppConstants.modrinthIndexFileName,
                type: .file,
                uncompressedSize: Int64(indexData.count),
                compressionMethod: .deflate
            ) { position, size -> Data in
                let start = Int(position)
                let end = min(start + size, indexData.count)
                return indexData.subdata(in: start..<end)
            }
        }

        // Add the overrides folder and all its contents to the zip root
        let overridesDir = tempDir.appendingPathComponent("overrides")
        if FileManager.default.fileExists(atPath: overridesDir.path) {
            let overridesEnumerator = FileManager.default.enumerator(
                at: overridesDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            // Normalize overridesDir path (make sure it ends with /)
            let overridesDirPath = (overridesDir.path as NSString).standardizingPath
            let overridesDirPathWithSlash = overridesDirPath.hasSuffix("/")
                ? overridesDirPath
                : overridesDirPath + "/"

            while let fileURL = overridesEnumerator?.nextObject() as? URL {
                if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                   isRegularFile {
                    // Calculate relative path (relative to overridesDir), add overrides/ prefix
                    // Use standardized paths to avoid problems caused by paths containing words like "private"
                    let filePath = (fileURL.path as NSString).standardizingPath

                    // Make sure the file path starts with the overridesDir path
                    guard filePath.hasPrefix(overridesDirPathWithSlash) else {
                        Logger.shared.warning("文件路径不在 overrides 目录内: \(filePath)")
                        continue
                    }

                    // Extract relative path part
                    let relativeToOverrides = String(filePath.dropFirst(overridesDirPathWithSlash.count))
                    // Path in build ZIP (starting with overrides/)
                    let relativePath = "overrides/\(relativeToOverrides)"

                    let fileData = try Data(contentsOf: fileURL)
                    let fileSize = Int64(fileData.count)

                    try archive.addEntry(
                        with: relativePath,
                        type: .file,
                        uncompressedSize: fileSize,
                        compressionMethod: .deflate
                    ) { position, size -> Data in
                        let start = Int(position)
                        let end = min(start + size, fileData.count)
                        return fileData.subdata(in: start..<end)
                    }
                }
            }
        }
    }
}

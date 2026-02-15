import Foundation

/// resource handler
/// Responsible for identifying resource files and deciding whether to add them to the index or copy them to overrides
enum ResourceProcessor {

    /// Processing results
    struct ProcessResult {
        let indexFile: ModrinthIndexFile?
        let shouldCopyToOverrides: Bool
        let sourceFile: URL
        let relativePath: String
    }

    /// Identify resource files (do not copy)
    /// - Parameters:
    ///   - file: resource file path
    ///   - resourceType: resource type
    /// - Returns: processing results
    static func identify(
        file: URL,
        resourceType: ResourceScanner.ResourceType
    ) async -> ProcessResult {
        let relativePath = resourceType.rawValue

        // Try to get information from Modrinth
        var indexFile: ModrinthIndexFile?
        if let modrinthInfo = await ModrinthResourceIdentifier.getModrinthInfo(for: file) {
            // Find the Modrinth project and try to create an index file
            indexFile = await createIndexFile(
                from: file,
                modrinthInfo: modrinthInfo,
                relativePath: relativePath
            )
        }

        // If the index file is successfully created, it does not need to be copied to overrides
        if let indexFile = indexFile {
            return ProcessResult(
                indexFile: indexFile,
                shouldCopyToOverrides: false,
                sourceFile: file,
                relativePath: relativePath
            )
        }

        // If the index file fails to be created (Modrinth cannot recognize it, the creation fails, etc.), it needs to be copied to overrides
        return ProcessResult(
            indexFile: nil,
            shouldCopyToOverrides: true,
            sourceFile: file,
            relativePath: relativePath
        )
    }

    /// Copy the files to the overrides directory
    /// - Parameters:
    ///   - file: source file path
    ///   - resourceType: resource type
    ///   - overridesDir: overrides directory
    /// - Throws: If copying files fails
    static func copyToOverrides(
        file: URL,
        resourceType: ResourceScanner.ResourceType,
        overridesDir: URL
    ) throws {
        let relativePath = resourceType.rawValue
        let overridesSubDir = overridesDir.appendingPathComponent(relativePath)
        let destPath = overridesSubDir.appendingPathComponent(file.lastPathComponent)

        try FileManager.default.createDirectory(at: overridesSubDir, withIntermediateDirectories: true)

        // If the target file already exists, delete it first
        if FileManager.default.fileExists(atPath: destPath.path) {
            try? FileManager.default.removeItem(at: destPath)
        }

        try FileManager.default.copyItem(at: file, to: destPath)
    }

    /// Process a single resource file (compatible with the old interface, identify first and then copy)
    /// - Parameters:
    ///   - file: resource file path
    ///   - resourceType: resource type
    ///   - overridesDir: overrides directory
    /// - Returns: processing results
    /// - Throws: If copying files fails
    static func process(
        file: URL,
        resourceType: ResourceScanner.ResourceType,
        overridesDir: URL
    ) async throws -> ProcessResult {
        // Identify first
        let result = await identify(file: file, resourceType: resourceType)

        // If copying is required, copy
        if result.shouldCopyToOverrides {
            try copyToOverrides(file: file, resourceType: resourceType, overridesDir: overridesDir)
        }

        return result
    }

    /// Create index file
    private static func createIndexFile(
        from modFile: URL,
        modrinthInfo: ModrinthResourceIdentifier.ModrinthModInfo,
        relativePath: String
    ) async -> ModrinthIndexFile? {
        // Calculate file hash
        guard let fileHash = try? SHA1Calculator.sha1(ofFileAt: modFile) else {
            return nil
        }

        // Matching files found
        let matchingFile = modrinthInfo.version.files.first { file in
            file.hashes.sha1 == fileHash
        } ?? modrinthInfo.version.files.first

        guard let matchingFile = matchingFile else {
            return nil
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: modFile.path)[.size] as? Int64) ?? 0

        // Set env field (clientSide and serverSide according to Modrinth project)
        // Map "optional" of Modrinth to "optional" and other values ​​to "required"
        let clientEnv = modrinthInfo.projectDetail.clientSide == "optional" ? "optional" : "required"
        let serverEnv = modrinthInfo.projectDetail.serverSide == "optional" ? "optional" : "required"

        let env = ModrinthIndexFileEnv(
            client: clientEnv,
            server: serverEnv
        )

        return ModrinthIndexFile(
            path: "\(relativePath)/\(modFile.lastPathComponent)",
            hashes: ModrinthIndexFileHashes(from: [
                "sha1": matchingFile.hashes.sha1,
                "sha512": matchingFile.hashes.sha512,
            ]),
            downloads: [matchingFile.url],
            fileSize: Int(fileSize),
            env: env,
            source: .modrinth
        )
    }
}

/// Modrinth Resource Identifier
/// Responsible for obtaining resource information from Modrinth
enum ModrinthResourceIdentifier {

    struct ModrinthModInfo {
        let projectDetail: ModrinthProjectDetail
        let version: ModrinthProjectDetailVersion
    }

    /// Try to get mod information from Modrinth
    /// Always query the API via hash
    static func getModrinthInfo(for modFile: URL) async -> ModrinthModInfo? {
        guard let hash = try? SHA1Calculator.sha1(ofFileAt: modFile) else {
            return nil
        }

        // Directly query the API via hash
        return await withCheckedContinuation { continuation in
            ModrinthService.fetchModrinthDetail(by: hash) { detail in
                guard let detail = detail else {
                    continuation.resume(returning: nil)
                    return
                }

                // Need to find matching version
                Task {
                    do {
                        let versions = try await ModrinthService.fetchProjectVersionsThrowing(id: detail.id)
                        // Find the version containing the hash
                        if let matchingVersion = versions.first(where: { version in
                            version.files.contains { $0.hashes.sha1 == hash }
                        }) {
                            continuation.resume(returning: ModrinthModInfo(
                                projectDetail: detail,
                                version: matchingVersion
                            ))
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

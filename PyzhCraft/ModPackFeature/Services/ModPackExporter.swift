import SwiftUI

/// Integrated package exporter
/// Export the game instance to Modrinth official modpack format (.mrpack)
enum ModPackExporter {

    // MARK: - Export Result

    struct ExportResult {
        let success: Bool
        let outputPath: URL?
        let error: Error?
        let message: String
    }

    // MARK: - Export Progress

    struct ExportProgress {
        var progress = 0.0
        var totalFiles = 0
        var processedFiles = 0

        // Multiple progress bars support
        struct ProgressItem {
            var title: LocalizedStringKey
            var progress: Double
            var currentFile: String
            var completed: Int
            var total: Int
        }

        var scanProgress: ProgressItem?
        var copyProgress: ProgressItem?
    }

    // MARK: - Main Export Function

    /// Export integration package
    /// - Parameters:
    ///   - gameInfo: game instance information
    ///   - outputPath: output file path
    ///   - modPackName: integration package name
    ///   - modPackVersion: integration package version
    ///   - summary: integration package description (optional)
    ///   - progressCallback: progress callback
    /// - Returns: export results
    static func exportModPack(
        gameInfo: GameVersionInfo,
        outputPath: URL,
        modPackName: String,
        modPackVersion: String = "1.0.0",
        summary: String? = nil,
        progressCallback: ((ExportProgress) -> Void)? = nil
    ) async -> ExportResult {
        var progress = ExportProgress()

        do {
            // 1. Prepare temporary directory
            progress.progress = 0.0
            progressCallback?(progress)

            let (tempDir, overridesDir) = try prepareDirectories()
            defer {
                // Clean up temporary directory
                try? FileManager.default.removeItem(at: tempDir)
            }

            // 2. Display the scanning progress bar first (before starting scanning)
            progress.progress = 0.1
            progress.scanProgress = ExportProgress.ProgressItem(
                title: "Scanning Resources",
                progress: 0.0,
                currentFile: "",
                completed: 0,
                total: 1
            )
            progressCallback?(progress)

            // Give the UI some time to render and make sure the progress bar is displayed first
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // 3. Scan all resource files
            let scanResults = try ResourceScanner.scanAllResources(gameInfo: gameInfo)
            let totalResources = ResourceScanner.totalFileCount(scanResults)
            let totalConfigFiles = try ConfigFileCopier.countFiles(gameInfo: gameInfo)
            let totalFiles = totalResources + totalConfigFiles
            progress.totalFiles = totalFiles

            // 4. Update the scanning progress bar to the actual value
            var initialProgress = progress
            initialProgress.scanProgress = ExportProgress.ProgressItem(
                title: "Scanning Resources",
                progress: totalResources > 0 ? 0.0 : 1.0,
                currentFile: "",
                completed: 0,
                total: max(totalResources, 1)
            )
            progressCallback?(initialProgress)

            // Give the UI some time to render
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // 5. Scan and identify all resource files
            progress.progress = 0.2
            progressCallback?(progress)

            let progressUpdater = ProgressUpdater(baseProgress: initialProgress)
            let processedCounter = ProcessedCounter()

            let (indexFiles, filesToCopy) = await scanAndIdentifyResources(
                gameInfo: gameInfo,
                scanResults: scanResults,
                totalResources: totalResources,
                progressUpdater: progressUpdater,
                processedCounter: processedCounter,
                progressCallback: progressCallback
            )

            // 6. Copy the resource files and configuration files that need to be copied
            progress.progress = 0.6
            progressCallback?(progress)

            let copyCounter = CopyCounter(total: filesToCopy.count + totalConfigFiles)

            try await copyFiles(
                params: CopyFilesParams(
                    filesToCopy: filesToCopy,
                    gameInfo: gameInfo,
                    overridesDir: overridesDir,
                    totalConfigFiles: totalConfigFiles
                ),
                copyCounter: copyCounter,
                progressUpdater: progressUpdater,
                progressCallback: progressCallback
            )

            // 7. Generate index files and package them
            try await buildIndexAndArchive(
                params: IndexBuildParams(
                    gameInfo: gameInfo,
                    modPackName: modPackName,
                    modPackVersion: modPackVersion,
                    summary: summary,
                    indexFiles: indexFiles
                ),
                tempDir: tempDir,
                outputPath: outputPath,
                progressUpdater: progressUpdater,
                progressCallback: progressCallback
            )

            return ExportResult(
                success: true,
                outputPath: outputPath,
                error: nil,
                message: ""
            )
        } catch {
            Logger.shared.error("导出整合包失败: \(error.localizedDescription)")
            return ExportResult(
                success: false,
                outputPath: nil,
                error: error,
                message: "导出失败: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helper Functions

    /// Create temporary directory
    private static func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modpack_export")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    // MARK: - Parameter Structures

    /// Index building parameters
    private struct IndexBuildParams {
        let gameInfo: GameVersionInfo
        let modPackName: String
        let modPackVersion: String
        let summary: String?
        let indexFiles: [ModrinthIndexFile]
    }

    /// File copy parameters
    private struct CopyFilesParams {
        let filesToCopy: [(file: URL, resourceType: ResourceScanner.ResourceType)]
        let gameInfo: GameVersionInfo
        let overridesDir: URL
        let totalConfigFiles: Int
    }

    /// Prepare temporary directory and overrides directory structure
    private static func prepareDirectories() throws -> (tempDir: URL, overridesDir: URL) {
        let tempDir = try createTempDirectory()
        let overridesDir = tempDir.appendingPathComponent("overrides")
        try FileManager.default.createDirectory(at: overridesDir, withIntermediateDirectories: true)

        // Create overrides subdirectories for various resources
        for resourceType in ResourceScanner.ResourceType.allCases {
            let subDir = overridesDir.appendingPathComponent(resourceType.rawValue)
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        }

        return (tempDir, overridesDir)
    }

    /// Scan and identify all resource files
    private static func scanAndIdentifyResources(
        gameInfo: GameVersionInfo,
        scanResults: [ResourceScanner.ResourceType: [URL]],
        totalResources: Int,
        progressUpdater: ProgressUpdater,
        processedCounter: ProcessedCounter,
        progressCallback: ((ExportProgress) -> Void)?
    ) async -> ([ModrinthIndexFile], [(file: URL, resourceType: ResourceScanner.ResourceType)]) {
        return await withTaskGroup(of: ResourceProcessor.ProcessResult.self) { group in
            for (resourceType, files) in scanResults {
                for file in files {
                    group.addTask {
                        // Only recognize, do not copy
                        let result = await ResourceProcessor.identify(
                            file: file,
                            resourceType: resourceType
                        )

                        // Update scan progress
                        let processed = await processedCounter.increment()
                        let scanTotal = max(totalResources, 1) // At least 1 to avoid divide-by-zero errors
                        let scanItem = ExportProgress.ProgressItem(
                            title: "Scanning Resources",
                            progress: Double(processed) / Double(scanTotal),
                            currentFile: result.sourceFile.lastPathComponent,
                            completed: processed,
                            total: scanTotal
                        )
                        await progressUpdater.updateScanProgress(scanItem)

                        // Get full progress and updates
                        let updatedProgress = await progressUpdater.getFullProgress()
                        progressCallback?(updatedProgress)

                        return result
                    }
                }
            }

            // Collect all results
            var indexFiles: [ModrinthIndexFile] = []
            var filesToCopy: [(file: URL, resourceType: ResourceScanner.ResourceType)] = []

            for await result in group {
                if let indexFile = result.indexFile {
                    // Modrinth resource successfully identified and added to index
                    indexFiles.append(indexFile)
                } else {
                    // Not recognized or failed to recognize, needs to be copied to overrides
                    if result.shouldCopyToOverrides {
                        if let resourceType = ResourceScanner.ResourceType(rawValue: result.relativePath) {
                            filesToCopy.append((file: result.sourceFile, resourceType: resourceType))
                        } else {
                            Logger.shared.warning("无法识别资源类型: \(result.relativePath)")
                        }
                    } else {
                        // This theoretically shouldn't happen, but the warning is logged just in case
                        Logger.shared.warning("资源文件既没有索引文件也不需要复制: \(result.sourceFile.lastPathComponent)")
                    }
                }
            }

            // If there are no resource files, make sure the scan progress bar shows Complete
            if totalResources == 0 {
                let completedScanItem = ExportProgress.ProgressItem(
                    title: "Scanning Resources",
                    progress: 1.0,
                    currentFile: "",
                    completed: 0,
                    total: 1
                )
                await progressUpdater.updateScanProgress(completedScanItem)
                let updatedProgress = await progressUpdater.getFullProgress()
                progressCallback?(updatedProgress)
            }

            return (indexFiles, filesToCopy)
        }
    }

    /// Copy resource files and configuration files
    private static func copyFiles(
        params: CopyFilesParams,
        copyCounter: CopyCounter,
        progressUpdater: ProgressUpdater,
        progressCallback: ((ExportProgress) -> Void)?
    ) async throws {
        let filesToCopy = params.filesToCopy
        let gameInfo = params.gameInfo
        let overridesDir = params.overridesDir
        let totalConfigFiles = params.totalConfigFiles
        let totalFilesToCopy = filesToCopy.count + totalConfigFiles

        // Update the total number of copy progress bars
        if totalFilesToCopy > 0 {
            await progressUpdater.setCopyProgressTotal(totalFilesToCopy)
            let currentProgress = await progressUpdater.getFullProgress()
            progressCallback?(currentProgress)
        }

        // Concurrently copy resource files and configuration files
        async let copyResourcesTask: Void = {
            await withTaskGroup(of: Void.self) { group in
                for (file, resourceType) in filesToCopy {
                    group.addTask {
                        do {
                            try ResourceProcessor.copyToOverrides(
                                file: file,
                                resourceType: resourceType,
                                overridesDir: overridesDir
                            )

                            // Update copy progress
                            let (processed, total) = await copyCounter.increment()
                            let copyItem = ExportProgress.ProgressItem(
                                title: "Copying Files",
                                progress: Double(processed) / Double(max(total, 1)),
                                currentFile: file.lastPathComponent,
                                completed: processed,
                                total: total
                            )
                            await progressUpdater.updateCopyProgress(copyItem)

                            // Get full progress and updates
                            let updatedProgress = await progressUpdater.getFullProgress()
                            progressCallback?(updatedProgress)
                        } catch {
                            Logger.shared.warning("复制资源文件失败: \(file.lastPathComponent), 错误: \(error.localizedDescription)")

                            // Update progress (counts as processed even if it fails)
                            let (processed, total) = await copyCounter.increment()
                            let copyItem = ExportProgress.ProgressItem(
                                title: "Copying Files",
                                progress: Double(processed) / Double(max(total, 1)),
                                currentFile: file.lastPathComponent,
                                completed: processed,
                                total: total
                            )
                            await progressUpdater.updateCopyProgress(copyItem)

                            // Get full progress and updates
                            let updatedProgress = await progressUpdater.getFullProgress()
                            progressCallback?(updatedProgress)
                        }
                    }
                }

                // Wait for all copy tasks to complete
                for await _ in group {}
            }
        }()

        async let copyConfigTask: Void = {
            try await ConfigFileCopier.copyFiles(
                gameInfo: gameInfo,
                to: overridesDir
            ) { _, currentFileName in
                Task {
                    // Update total progress using shared counter
                    let (processed, total) = await copyCounter.increment()
                    let copyItem = ExportProgress.ProgressItem(
                        title: "Copying Files",
                        progress: Double(processed) / Double(max(total, 1)),
                        currentFile: currentFileName,
                        completed: processed,
                        total: total
                    )
                    await progressUpdater.updateCopyProgress(copyItem)

                    // Get full progress and updates
                    let updatedProgress = await progressUpdater.getFullProgress()
                    progressCallback?(updatedProgress)
                }
            }
        }()

        // Wait for both copy tasks to complete
        await copyResourcesTask
        try await copyConfigTask
    }

    /// Generate index files and package them
    private static func buildIndexAndArchive(
        params: IndexBuildParams,
        tempDir: URL,
        outputPath: URL,
        progressUpdater: ProgressUpdater,
        progressCallback: ((ExportProgress) -> Void)?
    ) async throws {
        // Generate modrinth.index.json
        var currentProgress = await progressUpdater.getFullProgress()
        currentProgress.progress = 0.9
        progressCallback?(currentProgress)

        let indexJson = try await ModrinthIndexBuilder.build(
            gameInfo: params.gameInfo,
            modPackName: params.modPackName,
            modPackVersion: params.modPackVersion,
            summary: params.summary,
            files: params.indexFiles
        )

        let indexPath = tempDir.appendingPathComponent(AppConstants.modrinthIndexFileName)
        try indexJson.write(to: indexPath, atomically: true, encoding: String.Encoding.utf8)

        // Packed as .mrpack
        currentProgress = await progressUpdater.getFullProgress()
        currentProgress.progress = 0.95
        progressCallback?(currentProgress)

        try ModPackArchiver.archive(tempDir: tempDir, outputPath: outputPath)

        // Packaging is complete, make sure the progress bar shows 100%
        currentProgress = await progressUpdater.getFullProgress()
        currentProgress.progress = 1.0
        // Make sure both the scan and copy progress bars show 100%, but keep the last filename processed
        if var scanProgress = currentProgress.scanProgress {
            scanProgress.progress = 1.0
            scanProgress.completed = scanProgress.total
            currentProgress.scanProgress = scanProgress
        }
        if var copyProgress = currentProgress.copyProgress {
            copyProgress.progress = 1.0
            copyProgress.completed = copyProgress.total
            currentProgress.copyProgress = copyProgress
        }
        progressCallback?(currentProgress)
    }

    // MARK: - Progress Management Types

    /// progress updater
    private actor ProgressUpdater {
        private var scanProgress: ExportProgress.ProgressItem?
        private var copyProgress: ExportProgress.ProgressItem?
        private var baseProgress: ExportProgress

        init(baseProgress: ExportProgress) {
            self.baseProgress = baseProgress
        }

        func updateScanProgress(_ item: ExportProgress.ProgressItem) {
            scanProgress = item
        }

        func updateCopyProgress(_ item: ExportProgress.ProgressItem) {
            copyProgress = item
        }

        func setCopyProgressTotal(_ total: Int) {
            if let existing = copyProgress {
                copyProgress = ExportProgress.ProgressItem(
                    title: existing.title,
                    progress: existing.progress,
                    currentFile: existing.currentFile,
                    completed: existing.completed,
                    total: total
                )
            } else {
                copyProgress = ExportProgress.ProgressItem(
                    title: "Copying Files",
                    progress: 0.0,
                    currentFile: "",
                    completed: 0,
                    total: total
                )
            }
        }

        func getFullProgress() -> ExportProgress {
            var fullProgress = baseProgress
            fullProgress.scanProgress = scanProgress
            fullProgress.copyProgress = copyProgress
            return fullProgress
        }
    }

    /// Processed files counter
    private actor ProcessedCounter {
        private var count = 0

        func increment() -> Int {
            count += 1
            return count
        }

        func reset() {
            count = 0
        }
    }

    /// Copy progress counter
    private actor CopyCounter {
        private var count = 0
        private let total: Int

        init(total: Int) {
            self.total = total
        }

        func increment() -> (count: Int, total: Int) {
            count += 1
            return (count, total)
        }
    }
}

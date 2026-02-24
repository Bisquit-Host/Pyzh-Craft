import Foundation
import OSLog

enum ModrinthDependencyDownloader {
    /// Download all dependencies recursively (based on official dependency API)
    static func downloadAllDependenciesRecursive(
        for projectId: String,
        gameInfo: GameVersionInfo,
        query: String,
        gameRepository: GameRepository,
        actuallyDownloaded: inout [ModrinthProjectDetail],
        visited: inout Set<String>
    ) async {
        // Check if query is a valid resource type
        let validResourceTypes = ["mod", "datapack", "shader", "resourcepack"]
        let queryLowercased = query.lowercased()
        
        // If query is modpack or an invalid resource type, return directly
        if queryLowercased == "modpack" || !validResourceTypes.contains(queryLowercased) {
            Logger.shared.error("Downloading this type of resource is not supported: \(query)")
            return
        }
        
        do {
            let resourceDir = AppPaths.resourceDirectory(
                for: query,
                gameName: gameInfo.gameName
            )
            guard let resourceDirUnwrapped = resourceDir else { return }
            // 1. Get all dependencies
            
            // New logic: Use ModScanner to determine whether the corresponding resource directory has been installed
            let dependencies =
            await ModrinthService.fetchProjectDependencies(
                type: query,
                cachePath: resourceDirUnwrapped,
                id: projectId,
                selectedVersions: [gameInfo.gameVersion],
                selectedLoaders: [gameInfo.modLoader]
            )
            
            // 2. Get main mod details
            guard
                await ModrinthService.fetchProjectDetails(id: projectId) != nil
            else {
                Logger.shared.error("Unable to get main project details (ID: \(projectId))")
                return
            }
            
            // 3. The maximum number of concurrent reads, at least 1
            let semaphore = AsyncSemaphore(
                value: GeneralSettingsManager.shared.concurrentDownloads
            )  // Control the maximum number of concurrencies
            
            // 4. Download all dependencies and main mod concurrently and collect the results
            let allDownloaded: [ModrinthProjectDetail] = await withTaskGroup(
                of: ModrinthProjectDetail?.self
            ) { group in
                // rely
                for depVersion in dependencies.projects {
                    group.addTask {
                        await semaphore.wait()  // Limit concurrency
                        defer { Task { await semaphore.signal() } }
                        
                        // Get project details
                        guard
                            let projectDetail =
                                await ModrinthService.fetchProjectDetails(
                                    id: depVersion.projectId
                                )
                        else {
                            
                            Logger.shared.error(
                                "Unable to obtain dependent project details (ID: \(depVersion.projectId))"
                            )
                            Logger.shared.error(
                                "Unable to obtain sss project details (ID: \(depVersion.projectId))"
                            )
                            return nil
                        }
                        
                        // Use file information from version
                        let result = ModrinthService.filterPrimaryFiles(
                            from: depVersion.files
                        )
                        if let file = result {
                            let fileURL =
                            try? await DownloadManager.downloadResource(
                                for: gameInfo,
                                urlString: file.url,
                                resourceType: query,
                                expectedSha1: file.hashes.sha1
                            )
                            var detailWithFile = projectDetail
                            detailWithFile.fileName = file.filename
                            detailWithFile.type = query
                            // Add cache
                            if let fileURL = fileURL,
                               let hash = ModScanner.sha1Hash(of: fileURL) {
                                ModScanner.shared.saveToCache(
                                    hash: hash,
                                    detail: detailWithFile
                                )
                                // If it is a mod, add it to the installation cache
                                if query.lowercased() == "mod" {
                                    ModScanner.shared.addModHash(
                                        hash,
                                        to: gameInfo.gameName
                                    )
                                }
                            }
                            return detailWithFile
                        }
                        return nil
                    }
                }
                // main mod
                group.addTask {
                    await semaphore.wait()  // Limit concurrency
                    defer { Task { await semaphore.signal() } }
                    
                    do {
                        guard
                            var mainProjectDetail =
                                await ModrinthService.fetchProjectDetails(
                                    id: projectId
                                )
                        else {
                            Logger.shared.error("Unable to get main project details (ID: \(projectId))")
                            return nil
                        }
                        let filteredVersions =
                        try await ModrinthService.fetchProjectVersionsFilter(
                            id: projectId,
                            selectedVersions: [gameInfo.gameVersion],
                            selectedLoaders: [gameInfo.modLoader],
                            type: query
                        )
                        let result = ModrinthService.filterPrimaryFiles(
                            from: filteredVersions.first?.files
                        )
                        if let file = result {
                            let fileURL =
                            try? await DownloadManager.downloadResource(
                                for: gameInfo,
                                urlString: file.url,
                                resourceType: query,
                                expectedSha1: file.hashes.sha1
                            )
                            mainProjectDetail.fileName = file.filename
                            mainProjectDetail.type = query
                            // Add cache
                            if let fileURL = fileURL,
                               let hash = ModScanner.sha1Hash(of: fileURL) {
                                ModScanner.shared.saveToCache(
                                    hash: hash,
                                    detail: mainProjectDetail
                                )
                                // If it is a mod, add it to the installation cache
                                if query.lowercased() == "mod" {
                                    ModScanner.shared.addModHash(
                                        hash,
                                        to: gameInfo.gameName
                                    )
                                }
                            }
                            return mainProjectDetail
                        }
                        return nil
                    } catch {
                        let globalError = GlobalError.from(error)
                        Logger.shared.error(
                            "Download main resource \(projectId) failed: \(globalError.chineseMessage)"
                        )
                        GlobalErrorHandler.shared.handle(globalError)
                        return nil
                    }
                }
                // Collect all download results
                var localResults: [ModrinthProjectDetail] = []
                for await result in group {
                    if let project = result {
                        localResults.append(project)
                    }
                }
                return localResults
            }
            
            actuallyDownloaded.append(contentsOf: allDownloaded)
        }
    }
    
    /// Get missing dependencies (with version information)
    static func getMissingDependenciesWithVersions(
        for projectId: String,
        gameInfo: GameVersionInfo
    ) async -> [(
        detail: ModrinthProjectDetail, versions: [ModrinthProjectDetailVersion]
    )] {
        let query = "mod"
        let resourceDir = AppPaths.modsDirectory(
            gameName: gameInfo.gameName
        )
        
        let dependencies = await ModrinthService.fetchProjectDependencies(
            type: query,
            cachePath: resourceDir,
            id: projectId,
            selectedVersions: [gameInfo.gameVersion],
            selectedLoaders: [gameInfo.modLoader]
        )
        
        // Concurrently obtain details and version information of all dependent projects
        return await withTaskGroup(
            of: (ModrinthProjectDetail, [ModrinthProjectDetailVersion])?.self
        ) { group in
            for depVersion in dependencies.projects {
                group.addTask {
                    // Get project details
                    guard
                        let projectDetail =
                            await ModrinthService.fetchProjectDetails(
                                id: depVersion.projectId
                            )
                    else {
                        return nil
                    }
                    
                    // Use server-side filtering method, consistent with global resource installation logic
                    // Preset game versions and loaders
                    // fetchProjectVersionsFilter internally handles CurseForge projects
                    let filteredVersions: [ModrinthProjectDetailVersion]
                    do {
                        filteredVersions = try await ModrinthService.fetchProjectVersionsFilter(
                            id: depVersion.projectId,
                            selectedVersions: [gameInfo.gameVersion],
                            selectedLoaders: [gameInfo.modLoader],
                            type: "mod"
                        )
                    } catch {
                        // If version acquisition fails, an empty list is returned
                        Logger.shared.error("Failed to get version of dependency \(projectDetail.title): \(error.localizedDescription)")
                        filteredVersions = []
                    }
                    
                    return (projectDetail, filteredVersions)
                }
            }
            
            var results:
            [(
                detail: ModrinthProjectDetail,
                versions: [ModrinthProjectDetailVersion]
            )] = []
            for await result in group {
                if let (detail, versions) = result {
                    results.append((detail, versions))
                }
            }
            
            return results
        }
    }
    
    /// Get missing dependencies
    static func getMissingDependencies(
        for projectId: String,
        gameInfo: GameVersionInfo
    ) async -> [ModrinthProjectDetail] {
        let query = "mod"
        let resourceDir = AppPaths.modsDirectory(
            gameName: gameInfo.gameName
        )
        
        let dependencies = await ModrinthService.fetchProjectDependencies(
            type: query,
            cachePath: resourceDir,
            id: projectId,
            selectedVersions: [gameInfo.gameVersion],
            selectedLoaders: [gameInfo.modLoader]
        )
        
        // Convert ModrinthProjectDetailVersion to ModrinthProjectDetail
        var projectDetails: [ModrinthProjectDetail] = []
        for depVersion in dependencies.projects {
            if let projectDetail = await ModrinthService.fetchProjectDetails(
                id: depVersion.projectId
            ) {
                projectDetails.append(projectDetail)
            }
        }
        
        return projectDetails
    }
    
    // Manually download dependencies and main mod (not recursive, only current dependencies and main mod)
    // swiftlint:disable:next function_parameter_count
    static func downloadManualDependenciesAndMain(
        dependencies: [ModrinthProjectDetail],
        selectedVersions: [String: String],
        dependencyVersions: [String: [ModrinthProjectDetailVersion]],
        mainProjectId: String,
        mainProjectVersionId: String?,
        gameInfo: GameVersionInfo,
        query: String,
        gameRepository: GameRepository,
        onDependencyDownloadStart: @escaping (String) -> Void,
        onDependencyDownloadFinish: @escaping (String, Bool) -> Void
    ) async -> Bool {
        var resourcesToAdd: [ModrinthProjectDetail] = []
        var allSuccess = true
        let semaphore = AsyncSemaphore(
            value: GeneralSettingsManager.shared.concurrentDownloads
        )
        
        await withTaskGroup(of: (String, Bool, ModrinthProjectDetail?).self) { group in
            for dep in dependencies {
                guard let versionId = selectedVersions[dep.id],
                      let versions = dependencyVersions[dep.id],
                      let version = versions.first(where: { $0.id == versionId }),
                      let primaryFile = ModrinthService.filterPrimaryFiles(
                        from: version.files
                      )
                else {
                    allSuccess = false
                    Task { @MainActor in
                        onDependencyDownloadFinish(dep.id, false)
                    }
                    continue
                }
                
                group.addTask {
                    var depCopy = dep
                    let depId = depCopy.id
                    await MainActor.run { onDependencyDownloadStart(depId) }
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    
                    var success = false
                    do {
                        let fileURL =
                        try await DownloadManager.downloadResource(
                            for: gameInfo,
                            urlString: primaryFile.url,
                            resourceType: query,
                            expectedSha1: primaryFile.hashes.sha1
                        )
                        depCopy.fileName = primaryFile.filename
                        depCopy.type = query
                        success = true
                        // Add cache
                        if let hash = ModScanner.sha1Hash(of: fileURL) {
                            ModScanner.shared.saveToCache(
                                hash: hash,
                                detail: depCopy
                            )
                            // If it is a mod, add it to the installation cache
                            if query.lowercased() == "mod" {
                                ModScanner.shared.addModHash(
                                    hash,
                                    to: gameInfo.gameName
                                )
                            }
                        }
                    } catch {
                        let globalError = GlobalError.from(error)
                        Logger.shared.error(
                            "Download dependency \(depId) failed: \(globalError.chineseMessage)"
                        )
                        GlobalErrorHandler.shared.handle(globalError)
                        success = false
                    }
                    let depCopyFinal = depCopy
                    return (depId, success, success ? depCopyFinal : nil)
                }
            }
            
            for await (depId, success, depCopy) in group {
                await MainActor.run {
                    onDependencyDownloadFinish(depId, success)
                }
                if success, let depCopy = depCopy {
                    resourcesToAdd.append(depCopy)
                } else {
                    allSuccess = false
                }
            }
        }
        
        guard allSuccess else {
            // If the dependency download fails, it will not continue to download the main mod and will directly return failure
            return false
        }
        
        // All dependencies are successful, now download the main mod
        do {
            guard
                var mainProjectDetail =
                    await ModrinthService.fetchProjectDetails(id: mainProjectId)
            else {
                Logger.shared.error("Unable to get main project details (ID: \(mainProjectId))")
                return false
            }
            
            let selectedLoaders = [gameInfo.modLoader]
            let filteredVersions =
            try await ModrinthService.fetchProjectVersionsFilter(
                id: mainProjectId,
                selectedVersions: [gameInfo.gameVersion],
                selectedLoaders: selectedLoaders,
                type: query
            )
            
            // If a version ID is specified, use the specified version; otherwise use the latest version
            let targetVersion: ModrinthProjectDetailVersion
            if let mainProjectVersionId = mainProjectVersionId,
               let specifiedVersion = filteredVersions.first(where: {
                   $0.id == mainProjectVersionId
               }) {
                targetVersion = specifiedVersion
            } else if let latestVersion = filteredVersions.first {
                targetVersion = latestVersion
            } else {
                Logger.shared.error("Unable to find suitable version")
                return false
            }
            
            guard
                let primaryFile = ModrinthService.filterPrimaryFiles(
                    from: targetVersion.files
                )
            else {
                Logger.shared.error("Unable to find main file")
                return false
            }
            
            let fileURL = try await DownloadManager.downloadResource(
                for: gameInfo,
                urlString: primaryFile.url,
                resourceType: query,
                expectedSha1: primaryFile.hashes.sha1
            )
            mainProjectDetail.fileName = primaryFile.filename
            mainProjectDetail.type = query
            // Add cache
            if let hash = ModScanner.sha1Hash(of: fileURL) {
                ModScanner.shared.saveToCache(
                    hash: hash,
                    detail: mainProjectDetail
                )
                // If it is a mod, add it to the installation cache
                if query.lowercased() == "mod" {
                    ModScanner.shared.addModHash(
                        hash,
                        to: gameInfo.gameName
                    )
                }
            }
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error(
                "Download main resource \(mainProjectId) failed: \(globalError.chineseMessage)"
            )
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }
    
    /// - Returns: (success, fileName, hash), fileName and hash have values ​​when successful, and (false, nil, nil) when failed
    static func downloadMainResourceOnly(
        mainProjectId: String,
        gameInfo: GameVersionInfo,
        query: String,
        gameRepository: GameRepository,
        filterLoader: Bool = true
    ) async -> (Bool, fileName: String?, hash: String?) {
        do {
            guard
                var mainProjectDetail =
                    await ModrinthService.fetchProjectDetails(id: mainProjectId)
            else {
                Logger.shared.error("Unable to get main project details (ID: \(mainProjectId))")
                return (false, nil, nil)
            }
            let selectedLoaders = filterLoader ? [gameInfo.modLoader] : []
            let filteredVersions =
            try await ModrinthService.fetchProjectVersionsFilter(
                id: mainProjectId,
                selectedVersions: [gameInfo.gameVersion],
                selectedLoaders: selectedLoaders,
                type: query
            )
            guard let latestVersion = filteredVersions.first,
                  let primaryFile = ModrinthService.filterPrimaryFiles(
                    from: latestVersion.files
                  )
            else {
                return (false, nil, nil)
            }
            
            let fileURL = try await DownloadManager.downloadResource(
                for: gameInfo,
                urlString: primaryFile.url,
                resourceType: query,
                expectedSha1: primaryFile.hashes.sha1
            )
            mainProjectDetail.fileName = primaryFile.filename
            mainProjectDetail.type = query
            
            var hash: String?
            // Add cache
            if let h = ModScanner.sha1Hash(of: fileURL) {
                hash = h
                ModScanner.shared.saveToCache(
                    hash: h,
                    detail: mainProjectDetail
                )
                // If it is a mod, add it to the installation cache
                if query.lowercased() == "mod" {
                    ModScanner.shared.addModHash(
                        h,
                        to: gameInfo.gameName
                    )
                }
            }
            return (true, primaryFile.filename, hash)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error(
                "Downloading only main resource \(mainProjectId) failed: \(globalError.chineseMessage)"
            )
            GlobalErrorHandler.shared.handle(globalError)
            return (false, nil, nil)
        }
    }
}

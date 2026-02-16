import SwiftUI

struct GameLocalResourceView: View {
    let game: GameVersionInfo
    let query: String
    let header: AnyView?
    @Binding var selectedItem: SidebarItem
    @Binding var selectedProjectId: String?
    let refreshToken: UUID
    @Binding var searchText: String
    @State private var scannedResources: [ModrinthProjectDetail] = []
    @State private var isLoadingResources = false
    @State private var error: GlobalError?
    @State private var currentPage: Int = 1
    @State private var hasMoreResults: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var resourceDirectory: URL? // Save resource directory path
    @State private var allFiles: [URL] = [] // List of all files
    @State private var searchTimer: Timer? // Search for anti-shake timer
    @Binding var localFilter: LocalResourceFilter

    private static let pageSize: Int = 20
    private var pageSize: Int { Self.pageSize }

    // List of currently displayed resources (infinite scroll)
    private var displayedResources: [ModrinthProjectDetail] {
        scannedResources
    }

    /// List of files actually used for scanning under the current filter
    private var filesToScan: [URL] {
        switch localFilter {
        case .all:
            return allFiles
        case .disabled:
            // Only scan files with .disable suffix
            return allFiles.filter { $0.lastPathComponent.hasSuffix(".disable") }
        }
    }

    var body: some View {
        List {
            if let header {
                header
                    .listRowSeparator(.hidden)
            }
            listContent
            if isLoadingMore {
                loadingMoreIndicator
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search Resources"
        )
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                // When the page is initialized, load the first page resources (infinite scrolling)
                initializeResourceDirectory()
                resetPagination()
                refreshAllFiles()
                loadPage(page: 1, append: false)
            }
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
        .onChange(of: refreshToken) { _, _ in
            // Reset the resource directory to ensure that the directory of the new game is used when switching games
            resourceDirectory = nil
            resetPagination()
            refreshAllFiles()
            loadPage(page: 1, append: false)
        }
        .onChange(of: query) { oldValue, newValue in
            // When the resource type (query) changes, reinitialize the resource directory and refresh the file list
            if oldValue != newValue {
                resourceDirectory = nil
                resetPagination()
                refreshAllFiles()
                loadPage(page: 1, append: false)
            }
            // keep search text
            searchText = ""
        }
        .onChange(of: searchText) { oldValue, newValue in
            // When the search text changes, reset pagination and trigger anti-shake search
            if oldValue != newValue {
                resetPagination()
                debounceSearch()
            }
        }
        .onChange(of: localFilter) { _, _ in
            resourceDirectory = nil
            resetPagination()
            refreshAllFiles()
            loadPage(page: 1, append: false)
        }
        .alert(
            "Validation Error",
            isPresented: .constant(error != nil)
        ) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.chineseMessage)
            }
        }
    }

    // MARK: - List contents
    @ViewBuilder private var listContent: some View {
        if let error {
            VStack {
                Text(error.chineseMessage)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
        } else if isLoadingResources && scannedResources.isEmpty {
            HStack {
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
        } else if hasLoaded && displayedResources.isEmpty {
            EmptyView()
        } else {
            ForEach(
                displayedResources.map { ModrinthProject.from(detail: $0) },
                id: \.projectId
            ) { mod in
                ModrinthDetailCardView(
                    project: mod,
                    selectedVersions: [game.gameVersion],
                    selectedLoaders: [game.modLoader],
                    gameInfo: game,
                    query: query,
                    type: false,
                    selectedItem: $selectedItem,
                    onResourceChanged: refreshResources,
                    onLocalDisableStateChanged: handleLocalDisableStateChanged,
                    onResourceUpdated: handleResourceUpdated,
                    scannedDetailIds: .constant([])
                )
                .padding(.vertical, ModrinthConstants.UIConstants.verticalPadding)
                .listRowInsets(
                    EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                )
                .listRowSeparator(.hidden)
                .onTapGesture {
                    // Local resources do not jump to the details page (the original logic is used)
                    // Use id prefix to determine local resources, which is more reliable
                    if !mod.projectId.hasPrefix("local_") && !mod.projectId.hasPrefix("file_") {
                        selectedProjectId = mod.projectId
                        if let type = ResourceType(rawValue: query) {
                            selectedItem = .resource(type)
                        }
                    }
                }
                .onAppear {
                    loadNextPageIfNeeded(currentItem: mod)
                }
            }
        }
    }

    private var loadingMoreIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: - Loading in pages
    private func resetPagination() {
        currentPage = 1
        hasMoreResults = true
        isLoadingResources = false
        isLoadingMore = false
        error = nil
        scannedResources = []
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Clear search timer
        searchTimer?.invalidate()
        searchTimer = nil
        // NOTE: Search text is no longer cleared, user search status remains
        scannedResources = []
        isLoadingResources = false
        error = nil
        currentPage = 1
        hasMoreResults = true
        isLoadingMore = false
        hasLoaded = false
        resourceDirectory = nil
        allFiles = []
    }

    // MARK: - Search related
    /// Anti-shake search
    private func debounceSearch() {
        searchTimer?.invalidate()
        let currentSearchText = searchText
        searchTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: false
        ) { _ in
            // Check if search text has changed (avoid expired searches)
            if self.searchText == currentSearchText {
                self.loadPage(page: 1, append: false)
            }
        }
    }

    /// Filter resource details based on title and projectType
    private func filterResourcesByTitle(_ details: [ModrinthProjectDetail]) -> [ModrinthProjectDetail] {
        // Filter resource types by query
        let queryLower = query.lowercased()
        let filteredByType = details.filter { detail in
            // The local resource (starting with local_/file_) directory has been filtered by query, and the projectType of fallback is always mod
            if detail.id.hasPrefix("local_") || detail.id.hasPrefix("file_") {
                // Local resources: The directory has been filtered and displayed directly
                return true
            } else {
                // Resources obtained from API: filter based on projectType
                // Only display resource types matching query
                return detail.projectType.lowercased() == queryLower
            }
        }

        // Filter by search text
        let searchLower = searchText.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if searchLower.isEmpty {
            return filteredByType
        }

        return filteredByType.filter { detail in
            detail.title.lowercased().contains(searchLower)
        }
    }

    // MARK: - Resource directory initialization
    /// Initialize resource directory path
    private func initializeResourceDirectory() {
        // If resourceDirectory already exists, check if it matches the current game
        if let existingDir = resourceDirectory {
            let expectedDir = AppPaths.resourceDirectory(
                for: query,
                gameName: game.gameName
            )
            // If the directories do not match, reinitialization is required
            if existingDir != expectedDir {
                resourceDirectory = nil
            } else {
                return
            }
        }

        resourceDirectory = AppPaths.resourceDirectory(
            for: query,
            gameName: game.gameName
        )

        if resourceDirectory == nil {
            let globalError = GlobalError.configuration(
                i18nKey: "Resource Directory Not Found",
                level: .notification
            )
            Logger.shared.error("初始化资源目录失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            error = globalError
        }
    }

    // MARK: - file list
    private func refreshAllFiles() {
        // Modpacks don't have a local directory to scan
        if query.lowercased() == "modpack" {
            allFiles = []
            return
        }

        if resourceDirectory == nil {
            initializeResourceDirectory()
        }

        guard let resourceDir = resourceDirectory else {
            allFiles = []
            return
        }

        allFiles = ModScanner.shared.getAllResourceFiles(resourceDir)
    }

    private func loadPage(page: Int, append: Bool) {
        guard !isLoadingResources, !isLoadingMore else { return }

        // Modpacks don't have a local directory to scan, skip scanning
        if query.lowercased() == "modpack" {
            scannedResources = []
            isLoadingResources = false
            isLoadingMore = false
            hasMoreResults = false
            return
        }

        // Select the actual set of files to scan based on the current filter
        let sourceFiles = filesToScan

        if sourceFiles.isEmpty {
            scannedResources = []
            isLoadingResources = false
            isLoadingMore = false
            hasMoreResults = false
            return
        }

        if append {
            isLoadingMore = true
        } else {
            isLoadingResources = true
        }
        error = nil

        let isSearching = !searchText.isEmpty

        // Always use the file list under the current filter for paging scanning, and then filter based on title in the results
        ModScanner.shared.scanResourceFilesPage(
            fileURLs: sourceFiles,
            page: page,
            pageSize: pageSize
        ) { [self] details, hasMore in
            DispatchQueue.main.async {
                // Filter results based on title
                let filteredDetails = self.filterResourcesByTitle(details)

                if append {
                    // Append mode: only add matching results and remove duplicates
                    // Get the existing id collection for deduplication
                    let existingIds = Set(self.scannedResources.map { $0.id })
                    // Only add unique resources
                    let newDetails = filteredDetails.filter { !existingIds.contains($0.id) }
                    self.scannedResources.append(contentsOf: newDetails)
                } else {
                    // Replacement mode: directly use the filtered results
                    scannedResources = filteredDetails
                }

                // In search mode: If there are more pages, the next page will be automatically loaded until all files are searched
                if isSearching && hasMore {
                    // Reset the loading status first, then continue loading the next page
                    isLoadingResources = false
                    isLoadingMore = false
                    let nextPage = page + 1
                    self.currentPage = nextPage
                    // Continue loading the next page directly without judging the filtering results
                    self.loadPage(page: nextPage, append: true)
                } else {
                    // Not in search mode or all files have been searched
                    hasMoreResults = hasMore
                    isLoadingResources = false
                    isLoadingMore = false
                }
            }
        }
    }

    private func loadNextPageIfNeeded(currentItem mod: ModrinthProject) {
        guard hasMoreResults, !isLoadingResources, !isLoadingMore else {
            return
        }
        guard
            let index = scannedResources.firstIndex(where: {
                $0.id == mod.projectId
            })
        else { return }

        // Load next page when scrolling near the end of loaded list
        let thresholdIndex = max(scannedResources.count - 5, 0)
        if index >= thresholdIndex {
            currentPage += 1
            let nextPage = currentPage
            loadPage(page: nextPage, append: true)
        }
    }

    // MARK: - Refresh resources
    /// Refresh the resource list (called after deleting the resource)
    private func refreshResources() {
        // Refresh file list
        refreshAllFiles()
        // Reset pagination and reload first page
        resetPagination()
        loadPage(page: 1, append: false)
    }

    /// Processing after local resource enable/disable status changes
    /// - Parameters:
    ///   - project: the corresponding ModrinthProject (converted from detail, its fileName is the old value before switching)
    ///   - isDisabled: changed disabled state
    private func handleLocalDisableStateChanged(
        project: ModrinthProject,
        isDisabled: Bool
    ) {
        // Synchronously update the fileName of the corresponding entry in scannedResources to avoid state rollback when scrolling multiplexed rows
        guard let oldFileName = project.fileName else { return }
        let newFileName: String
        if isDisabled {
            newFileName = oldFileName + ".disable"
        } else {
            newFileName = oldFileName.hasSuffix(".disable")
                ? String(oldFileName.dropLast(".disable".count))
                : oldFileName
        }
        if let i = scannedResources.firstIndex(where: { $0.id == project.projectId }) {
            var d = scannedResources[i]
            d.fileName = newFileName
            scannedResources[i] = d
        }
        // Update allFiles synchronously to keep it consistent with the disk
        let resourceDir = resourceDirectory ?? AppPaths.resourceDirectory(
            for: query,
            gameName: game.gameName
        )
        if let dir = resourceDir,
           let j = allFiles.firstIndex(where: { $0.lastPathComponent == oldFileName }) {
            allFiles[j] = dir.appendingPathComponent(newFileName)
        }
        // Under "Disabled" filtering, when a resource is enabled, remove the resource from the current results; no rescan is required
        if localFilter == .disabled, !isDisabled {
            scannedResources.removeAll { $0.id == project.projectId }
        }
    }

    /// Partial refresh after successful update: only update the hash and list items of the current entry, no global scan
    /// - Parameters:
    ///   - projectId: project id
    ///   - oldFileName: file name before update (used for replacement in allFiles)
    ///   - newFileName: new file name
    ///   - newHash: new file hash (ModScanner cache has been updated by the downloader, only reserved here)
    private func handleResourceUpdated(
        projectId: String,
        oldFileName: String,
        newFileName: String,
        newHash: String?
    ) {
        // Update the fileName of the corresponding entry in scannedResources
        if let i = scannedResources.firstIndex(where: { $0.id == projectId }) {
            var d = scannedResources[i]
            d.fileName = newFileName
            scannedResources[i] = d
        }
        // Update allFiles: Replace the old file URL with the new file URL to avoid inconsistency with subsequent paging
        let resourceDir = resourceDirectory ?? AppPaths.resourceDirectory(
            for: query,
            gameName: game.gameName
        )
        if let dir = resourceDir, let j = allFiles.firstIndex(where: { $0.lastPathComponent == oldFileName }) {
            allFiles[j] = dir.appendingPathComponent(newFileName)
        }
    }

    /// Toggle resource enable/disable status
    private func toggleResourceState(_ mod: ModrinthProject) {
        guard let resourceDir = resourceDirectory ?? AppPaths.resourceDirectory(
            for: query,
            gameName: game.gameName
        ) else {
            Logger.shared.error("切换资源启用状态失败：资源目录不存在")
            return
        }

        guard let fileName = mod.fileName else {
            Logger.shared.error("切换资源启用状态失败：缺少文件名")
            return
        }

        let fileManager = FileManager.default
        let currentURL = resourceDir.appendingPathComponent(fileName)
        let targetFileName: String

        let isDisabled = fileName.hasSuffix(".disable")
        if isDisabled {
            guard fileName.hasSuffix(".disable") else {
                Logger.shared.error("启用资源失败：文件后缀不包含 .disable")
                return
            }
            targetFileName = String(fileName.dropLast(".disable".count))
        } else {
            targetFileName = fileName + ".disable"
        }

        let targetURL = resourceDir.appendingPathComponent(targetFileName)

        do {
            try fileManager.moveItem(at: currentURL, to: targetURL)
        } catch {
            Logger.shared.error("切换资源启用状态失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(GlobalError(type: .resource, i18nKey: "Toggle state failed",
                level: .notification
            ))
        }
    }
}

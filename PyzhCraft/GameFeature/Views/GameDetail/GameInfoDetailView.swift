import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window Delegate
// NSWindowDelegate related code has been removed and is no longer needed for pure SwiftUI

// MARK: - Views
struct GameInfoDetailView: View {
    let game: GameVersionInfo

    @Binding var query: String
    @Binding var dataSource: DataSource
    @Binding var selectedVersions: [String]
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpact: [String]
    @Binding var selectedProjectId: String?
    @Binding var selectedLoaders: [String]
    @Binding var gameType: Bool  // false = local,   = server
    @EnvironmentObject var gameRepository: GameRepository
    @Binding var selectedItem: SidebarItem
    @Binding var searchText: String
    @Binding var localResourceFilter: LocalResourceFilter
    @StateObject private var cacheManager = CacheManager()
    @State private var localRefreshToken = UUID()

    // Scan results: detailId Set, used for fast search (O(1))
    @State private var scannedResources: Set<String> = []

    // Use stable headers to avoid rebuilds caused by cacheInfo updates
    @State private var remoteHeader: AnyView?
    @State private var localHeader: AnyView?

    // File picker status
    @State private var showIconFilePicker = false

    var body: some View {
        return Group {
            if gameType {
                GameRemoteResourceView(
                    game: game,
                    query: $query,
                    selectedVersions: $selectedVersions,
                    selectedCategories: $selectedCategories,
                    selectedFeatures: $selectedFeatures,
                    selectedResolutions: $selectedResolutions,
                    selectedPerformanceImpact: $selectedPerformanceImpact,
                    selectedProjectId: $selectedProjectId,
                    selectedLoaders: $selectedLoaders,
                    selectedItem: $selectedItem,
                    gameType: $gameType,
                    header: remoteHeader,
                    scannedDetailIds: $scannedResources,
                    dataSource: $dataSource,
                    searchText: $searchText
                )
            } else {
                GameLocalResourceView(
                    game: game,
                    query: query,
                    header: localHeader,
                    selectedItem: $selectedItem,
                    selectedProjectId: $selectedProjectId,
                    refreshToken: localRefreshToken,
                    searchText: $searchText,
                    localFilter: $localResourceFilter
                )
            }
        }
        // Refresh logic:
        // 1. Refresh when the game name changes
        // 2. Refresh when the gameType changes and the game name remains unchanged
        .onChange(of: game.gameName) { _, _ in
            // Refresh when game name changes
            performRefresh()
        }
        .onChange(of: gameType) { _, _ in
            performRefresh()
        }
        // 4. When the details are closed (selectedProjectId changes from non-nil to nil), the installed resources are rescanned
        //    Used to refresh the installation status in the remote list (install button)
        .onChange(of: selectedProjectId) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                resetScanState()
                scanAllResources()
            }
        }
        // 3. When the resource type (query) changes, the installed resources are rescanned to update the installation status
        .onChange(of: query) { _, _ in
            resetScanState()
            scanAllResources()
        }
        .onAppear {
            // initialize header
            updateHeaders()
            cacheManager.calculateGameCacheInfo(game.gameName)
        }
        .onChange(of: cacheManager.cacheInfo) { _, _ in
            // When cacheInfo is updated, update the header (but don't rebuild the entire view)
            updateHeaders()
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
        .fileImporter(
            isPresented: $showIconFilePicker,
            allowedContentTypes: [.png, .jpeg, .gif],
            allowsMultipleSelection: false
        ) { result in
            handleIconFileSelection(result)
        }
    }

    // MARK: - Refresh logic
    /// Perform refresh operation (called when the game name changes or gameType changes and the game name remains unchanged)
    private func performRefresh() {
        updateHeaders()
        cacheManager.calculateGameCacheInfo(game.gameName)
        // Refresh local resources only when viewed locally
        if !gameType {
            triggerLocalRefresh()
        }
        // Rescan resources
        resetScanState()
        scanAllResources()
    }

    private func triggerLocalRefresh() {
        // Only update refresh token when viewing locally
        guard !gameType else { return }
        localRefreshToken = UUID()
    }

    // MARK: - Update Header
    /// Update the header view without rebuilding the entire GameRemoteResourceView
    private func updateHeaders() {
        // Try to get the latest game information from gameRepository, if not found use the passed in game
        let currentGame = gameRepository.games.first { $0.id == game.id } ?? game

        remoteHeader = AnyView(
            GameHeaderListRow(
                game: currentGame,
                cacheInfo: cacheManager.cacheInfo,
                query: query,
                onImport: {
                    triggerLocalRefresh()
                },
                onIconTap: {
                    showIconFilePicker = true
                }
            )
        )
        localHeader = AnyView(
            GameHeaderListRow(
                game: currentGame,
                cacheInfo: cacheManager.cacheInfo,
                query: query,
                onImport: {
                    triggerLocalRefresh()
                },
                onIconTap: {
                    showIconFilePicker = true
                }
            )
        )
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Reset cache information to default values
        cacheManager.cacheInfo = CacheInfo(fileCount: 0, totalSize: 0)
        // Reset refresh token only when viewing locally
        if !gameType {
            localRefreshToken = UUID()
        }
        // Reset scan results
        scannedResources = []
    }

    // MARK: - Reset scan status
    /// Reset scan status and prepare to scan again
    private func resetScanState() {
        scannedResources = []
    }

    // MARK: - Scan all resources
    /// Asynchronously scan all resources and collect detailId (without blocking view rendering)
    private func scanAllResources() {
        // Modpacks don't have a local directory to scan
        if query.lowercased() == "modpack" {
            scannedResources = []
            return
        }

        guard let resourceDir = AppPaths.resourceDirectory(
            for: query,
            gameName: game.gameName
        ) else {
            scannedResources = []
            return
        }

        // Check if the directory exists and is accessible
        guard FileManager.default.fileExists(atPath: resourceDir.path) else {
            // The directory does not exist, return directly
            scannedResources = []
            return
        }

        // Use Task to create asynchronous tasks to ensure that view rendering is not blocked
        // All time-consuming operations are performed on the background thread and only return to the main thread when the status is updated
        Task {
            do {
                // Call the new asynchronous interface and only get the detailId (return Set directly)
                let detailIds = try await ModScanner.shared.scanAllDetailIdsThrowing(in: resourceDir)

                // Return to main thread update status
                await MainActor.run {
                    scannedResources = detailIds
                }
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("扫描所有资源失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)

                // Return to main thread update status
                await MainActor.run {
                    scannedResources = []
                }
            }
        }
    }

    // MARK: - Handles icon file selection
    /// Process user-selected icon files
    private func handleIconFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                let globalError = GlobalError.validation(
                    chineseMessage: "未选择文件",
                    i18nKey: "error.validation.no_file_selected",
                    level: .notification
                )
                GlobalErrorHandler.shared.handle(globalError)
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                let globalError = GlobalError.fileSystem(
                    chineseMessage: "无法访问所选文件",
                    i18nKey: "error.filesystem.file_access_failed",
                    level: .notification
                )
                GlobalErrorHandler.shared.handle(globalError)
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let gameName = game.gameName
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let imageData = try Data(contentsOf: url)
                        let profileDir = AppPaths.profileDirectory(gameName: gameName)
                        let iconFileName = AppConstants.defaultGameIcon
                        let iconURL = profileDir.appendingPathComponent(iconFileName)
                        try FileManager.default.createDirectory(
                            at: profileDir,
                            withIntermediateDirectories: true
                        )
                        try imageData.write(to: iconURL)
                    }.value

                    await MainActor.run {
                        IconRefreshNotifier.shared.notifyRefresh(for: gameName)
                        updateHeaders()
                    }
                    Logger.shared.info("成功更新游戏图标: \(gameName)")
                } catch {
                    let globalError = GlobalError.from(error)
                    Logger.shared.error("更新游戏图标失败: \(globalError.chineseMessage)")
                    GlobalErrorHandler.shared.handle(globalError)
                }
            }
        case .failure(let error):
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }
    }
}

import SwiftUI
import OSLog

struct AddOrDeleteResourceButton: View {
    var project: ModrinthProject
    let selectedVersions: [String]
    let selectedLoaders: [String]
    let gameInfo: GameVersionInfo?
    let query: String
    let type: Bool  // false = local, true = server
    @Binding var scannedDetailIds: Set<String> // detailId Set of scanned resources for fast lookup (O(1))
    @EnvironmentObject private var gameRepository: GameRepository
    @EnvironmentObject private var playerListViewModel: PlayerListViewModel
    @State private var addButtonState: ModrinthDetailCardView.AddButtonState =
        .idle
    @State private var isUpdateButtonLoading = false  // Update the loading state of the button
    @State private var showDeleteAlert = false

    @State private var activeAlert: ResourceButtonAlertType?
    @State private var showGlobalResourceSheet = false
    @State private var showModPackDownloadSheet = false  // New: Integrated package download sheet
    @State private var showGameResourceInstallSheet = false  // New: game resource installation sheet
    @State private var preloadedDetail: ModrinthProjectDetail?  // Preloaded project details (general: integration package/general resources)
    @State private var preloadedCompatibleGames: [GameVersionInfo] = []  // Pre-detected list of compatible games
    @State private var isDisabled = false  // Whether the resource is disabled
    @Binding var isResourceDisabled: Bool  // Disabled state exposed to parent view (used for graying effect)
    @State private var currentFileName: String?  // Current filename (tracks the renamed filename)
    @State private var hasDownloadedInSheet = false  // Mark whether the download is successful in the sheet
    @State private var oldFileNameForUpdate: String?  // Old file name before update (used to delete old files when updating)
    @Binding var selectedItem: SidebarItem
    var onResourceChanged: (() -> Void)?
    /// Enable/disable callback after state switching (only used by local resource list)
    var onToggleDisableState: ((Bool) -> Void)?
    /// Update success callback: Only the hash and list items of the current entry are updated, and no global scan is performed. Parameters (projectId, oldFileName, newFileName, newHash)
    var onResourceUpdated: ((String, String, String, String?) -> Void)?
    // Ensure all init has onResourceChanged parameter (with default value)
    init(
        project: ModrinthProject,
        selectedVersions: [String],
        selectedLoaders: [String],
        gameInfo: GameVersionInfo?,
        query: String,
        type: Bool,
        selectedItem: Binding<SidebarItem>,
        onResourceChanged: (() -> Void)? = nil,
        scannedDetailIds: Binding<Set<String>> = .constant([]),
        isResourceDisabled: Binding<Bool> = .constant(false),
        onResourceUpdated: ((String, String, String, String?) -> Void)? = nil,
        onToggleDisableState: ((Bool) -> Void)? = nil
    ) {
        self.project = project
        self.selectedVersions = selectedVersions
        self.selectedLoaders = selectedLoaders
        self.gameInfo = gameInfo
        self.query = query
        self.type = type
        self._selectedItem = selectedItem
        self.onResourceChanged = onResourceChanged
        self._scannedDetailIds = scannedDetailIds
        self._isResourceDisabled = isResourceDisabled
        self.onResourceUpdated = onResourceUpdated
        self.onToggleDisableState = onToggleDisableState
    }

    var body: some View {

        HStack(spacing: 8) {
            // Update button (only displayed in local mode and when there is an update)
            if type == false && addButtonState == .update {
                Button(action: handleUpdateAction) {
                    if isUpdateButtonLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("Update")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .font(.caption2)
                .controlSize(.small)
                .disabled(addButtonState == .loading || isUpdateButtonLoading)
            }

            // Disable/enable button (only displayed for local resources)
            if type == false {
                Toggle("", isOn: Binding(
                    get: { !isDisabled },
                    set: { _ in toggleDisableState() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            }

            // install/remove button
            Button(action: handleButtonAction) {
                buttonLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)  // Or .tint(.primary) but generally using accentColor is more beautiful
            .font(.caption2)
            .controlSize(.small)
            .disabled(
                addButtonState == .loading
                    || (addButtonState == .installed && type)
            )  // type = true (server mode) disables deletion
            .onAppear {
                if type == false {
                    // The local area is directly displayed as installed
                    addButtonState = .installed
                    // Initialize the current file name
                    if currentFileName == nil {
                        currentFileName = project.fileName
                    }
                    updateDisableState()
                    // Detect if there is a new version (only in local mode)
                    checkForUpdate()
                } else {
                    updateButtonState()
                }
            }
            // When the hash set of installed resources changes (such as rescanning after installing or deleting resources),
            // Refresh button installation status based on latest scan results
            .onChange(of: scannedDetailIds) { _, _ in
                if type {
                    updateButtonState()
                }
            }
            .confirmationDialog(
                "Delete",
                isPresented: $showDeleteAlert,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteFile()
                }
                .keyboardShortcut(.defaultAction)  // Bind the Enter key

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(project.title)\"? Deletion may cause game launch failure")
            }
            .sheet(
                isPresented: $showGlobalResourceSheet,
                onDismiss: {
                    addButtonState = .idle
                    // Clean up preloaded data when sheet is closed
                    preloadedDetail = nil
                    preloadedCompatibleGames = []
                },
                content: {
                    GlobalResourceSheet(
                        project: project,
                        resourceType: query,
                        isPresented: $showGlobalResourceSheet,
                        preloadedDetail: preloadedDetail,
                        preloadedCompatibleGames: preloadedCompatibleGames
                    )
                    .environmentObject(gameRepository)
                    .onDisappear {
                        // Clean up preloaded data when sheet is closed
                        preloadedDetail = nil
                        preloadedCompatibleGames = []
                    }
                }
            )
            // New: Integrated package download sheet
            .sheet(
                isPresented: $showModPackDownloadSheet,
                onDismiss: {
                    addButtonState = .idle
                    // Clean up preloaded data when sheet is closed
                    preloadedDetail = nil
                },
                content: {
                    ModPackDownloadSheet(
                        projectId: project.projectId,
                        gameInfo: gameInfo,
                        query: query,
                        preloadedDetail: preloadedDetail
                    )
                    .environmentObject(gameRepository)
                    .onDisappear {
                        // Clean up preloaded data when sheet is closed
                        preloadedDetail = nil
                    }
                }
            )
            // New: Game resource installation sheet (reuse global resource installation logic, preset game information)
            .sheet(
                isPresented: $showGameResourceInstallSheet,
                onDismiss: {
                    // Reset the loading state of the update button
                    isUpdateButtonLoading = false
                    // If the download is successful, the status has been set in the sheet
                    // If you just close the sheet (no downloading) or the download fails
                    if !hasDownloadedInSheet {
                        // If the update operation is canceled (oldFileNameForUpdate is not empty), keep the updated status
                        // Otherwise set to installation status
                        if oldFileNameForUpdate != nil {
                            // Cancel the update operation and keep the update button displayed
                            // No need to change addButtonState, keep .update state
                        } else {
                            addButtonState = .idle
                        }
                        // If the update operation is canceled or the download fails, clean up the old file names (without deleting the files)
                        // Old files will only be deleted if the download is successful
                        oldFileNameForUpdate = nil
                    }
                    // Reset download flag
                    hasDownloadedInSheet = false
                    // Clean preloaded data
                    preloadedDetail = nil
                },
                content: {
                    if let gameInfo = gameInfo {
                        GameResourceInstallSheet(
                            project: project,
                            resourceType: query,
                            gameInfo: gameInfo,
                            isPresented: $showGameResourceInstallSheet,
                            preloadedDetail: preloadedDetail,
                            isUpdateMode: oldFileNameForUpdate != nil
                        ) { newFileName, newHash in
                            // Download successful, mark and update status
                            hasDownloadedInSheet = true
                            addToScannedDetailIds(hash: newHash)

                            let wasUpdate = (oldFileNameForUpdate != nil)
                            let oldF = oldFileNameForUpdate
                            // If it is an update operation, delete the old file first (isUpdate: true does not trigger onResourceChanged)
                            if let old = oldF {
                                deleteFile(fileName: old, isUpdate: true)
                                oldFileNameForUpdate = nil
                            }
                            // Update process: only refresh the hash and list items of the current entry, no global scan
                            if wasUpdate, let new = newFileName, let old = oldF {
                                onResourceUpdated?(project.projectId, old, new, newHash)
                                currentFileName = new
                            } else if !type {
                                currentFileName = nil
                            }
                            if type == false {
                                checkForUpdate()
                            } else {
                                addButtonState = .installed
                            }
                            preloadedDetail = nil
                        }
                        .environmentObject(gameRepository)
                    }
                }
            )
        }
        .alert(item: $activeAlert) { alertType in
            alertType.alert
        }
    }

    // MARK: - UI Components
    private var buttonLabel: some View {
        switch addButtonState {
        case .idle:
            AnyView(Text("Install"))
        case .loading:
            AnyView(
                ProgressView()
                    .controlSize(.mini)
                    .font(.body)  // Set font size
            )
        case .installed:
            AnyView(
                Text(
                    (!type
                        ? LocalizedStringKey("Delete")
                        : LocalizedStringKey("Installed"))
                )
            )
        case .update:
            // When there is an update, the main button shows Delete (the update button is already shown separately on the left)
            AnyView(Text("Delete"))
        }
    }

    // Delete files based on file name
    private func deleteFile() {
        // Delete using project.fileName
        deleteFile(fileName: project.fileName)
    }

    // Delete files based on specified file name
    // - Parameter isUpdate: If true, it means it comes from the update process (deleting old files) and onResourceChanged is not called
    private func deleteFile(fileName: String?, isUpdate: Bool = false) {
        // Check if query is a valid resource type
        let validResourceTypes = ["mod", "datapack", "shader", "resourcepack"]
        let queryLowercased = query.lowercased()

        // If query is a modpack or an invalid resource type, show an error
        if queryLowercased == "modpack" || !validResourceTypes.contains(queryLowercased) {
            let globalError = GlobalError.configuration(
                i18nKey: "Delete File Failed",
                level: .notification
            )
            Logger.shared.error("Failed to delete file: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return
        }

        guard let gameInfo = gameInfo,
            let resourceDir = AppPaths.resourceDirectory(
                for: query,
                gameName: gameInfo.gameName
            )
        else {
            let globalError = GlobalError.configuration(
                i18nKey: "Delete File Failed",
                level: .notification
            )
            Logger.shared.error("Failed to delete file: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return
        }

        // Delete using the fileName passed in
        guard let fileName = fileName else {
            let globalError = GlobalError(
                type: .resource,
                i18nKey: "File name missing",
                level: .notification
            )
            Logger.shared.error("Failed to delete file: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return
        }

        let fileURL = resourceDir.appendingPathComponent(fileName)
        GameResourceHandler.performDelete(fileURL: fileURL)
        if !isUpdate {
            onResourceChanged?()
        }
    }

    // MARK: - Actions
    /// Handling update button clicks
    @MainActor
    private func handleUpdateAction() {
        if !type {
            // Save old file name for deletion after update
            oldFileNameForUpdate = currentFileName ?? project.fileName
            isUpdateButtonLoading = true
            Task {
                // Load project details and open the game resource installation sheet (reuse global resource installation logic)
                await loadGameResourceInstallDetailBeforeOpeningSheet()
            }
        }
    }

    @MainActor
    private func handleButtonAction() {
        if case .game = selectedItem {
            switch addButtonState {
            case .idle:
                // New: Special handling of modpacks
                if query == "modpack" {
                            addButtonState = .loading
                            Task {
                                await loadModPackDetailBeforeOpeningSheet()
                            }
                    return
                }

                addButtonState = .loading
                Task {
                    // Load project details and open the game resource installation sheet (reuse global resource installation logic)
                    await loadGameResourceInstallDetailBeforeOpeningSheet()
                }
            case .installed, .update:
                // When there is an update, the main button displays Delete, and the delete operation is performed after clicking it
                if !type {
                    showDeleteAlert = true
                }
            default:
                break
            }
        } else if case .resource = selectedItem {
            switch addButtonState {
            case .idle:
                // Special handling when type is true (server mode)
                if type {
                    // Special processing for integration packages: only need to determine whether there are players
                    if query == "modpack" {
                        if playerListViewModel.currentPlayer == nil {
                            activeAlert = .noPlayer
                            return
                        }
                        addButtonState = .loading
                        Task {
                            await loadModPackDetailBeforeOpeningSheet()
                        }
                        return
                    }

                    // Other resources: The game needs to exist before you can click it
                    if gameRepository.games.isEmpty {
                        activeAlert = .noGame
                        return
                    }
                } else {
                    // Original logic when type is false (local mode)
                    if query == "modpack" {
                        addButtonState = .loading
                        Task {
                            await loadModPackDetailBeforeOpeningSheet()
                        }
                        return
                    }
                }

                addButtonState = .loading
                Task {
                    // Open the GlobalResourceSheet to select the game to install
                    await loadProjectDetailBeforeOpeningSheet()
                }
            case .installed, .update:
                // When there is an update, the main button displays Delete, and the delete operation is performed after clicking it
                if !type {
                    showDeleteAlert = true
                }
            default:
                break
            }
        }
    }

    private func updateButtonState() {
        if type == false {
            addButtonState = .installed
            return
        }

        let validResourceTypes = ["mod", "datapack", "shader", "resourcepack"]
        let queryLowercased = query.lowercased()

        // modpack currently does not support installation status detection
        guard queryLowercased != "modpack",
              validResourceTypes.contains(queryLowercased)
        else {
            addButtonState = .idle
            return
        }

        // Only when the game is selected and in server mode, try to determine the installed status through hash
        guard case .game = selectedItem else {
            addButtonState = .idle
            return
        }

        // Set loading state before detection starts
        addButtonState = .loading

        Task {
            let installed = await ResourceInstallationChecker.checkInstalledStateForServerMode(
                project: project,
                resourceType: queryLowercased,
                installedHashes: scannedDetailIds,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders,
                gameInfo: gameInfo
            )
            await MainActor.run {
                addButtonState = installed ? .installed : .idle
            }
        }
    }

    // New: Load projectDetail (normal resources) before opening sheet
    private func loadProjectDetailBeforeOpeningSheet() async {
        defer {
            Task { @MainActor in
                addButtonState = .idle
            }
        }

        guard let result = await ResourceDetailLoader.loadProjectDetail(
            projectId: project.projectId,
            gameRepository: gameRepository,
            resourceType: query
        ) else {
            return
        }

        await MainActor.run {
            preloadedDetail = result.detail
            preloadedCompatibleGames = result.compatibleGames
            showGlobalResourceSheet = true
        }
    }

    // New: Load projectDetail before opening integration package sheet
    private func loadModPackDetailBeforeOpeningSheet() async {
        defer {
            Task { @MainActor in
                addButtonState = .idle
            }
        }

        guard let detail = await ResourceDetailLoader.loadModPackDetail(
            projectId: project.projectId
        ) else {
            return
        }

        await MainActor.run {
            preloadedDetail = detail
            showModPackDownloadSheet = true
        }
    }

    // New: Load project details before opening the game resource installation sheet (reuse global resource installation logic)
    private func loadGameResourceInstallDetailBeforeOpeningSheet() async {
        guard gameInfo != nil else {
            await MainActor.run {
                addButtonState = .idle
            }
            return
        }

        defer {
            Task { @MainActor in
                // Reset the loading state of the update button
                isUpdateButtonLoading = false
                // Only reset state during non-update operations
                // If it is an update operation (oldFileNameForUpdate is not empty), keep the current state
                if oldFileNameForUpdate == nil {
                    addButtonState = .idle
                }
            }
        }

        // Reset download flag
        await MainActor.run {
            hasDownloadedInSheet = false
        }

        // Load project details (uses the same logic as global resource installation)
        guard let result = await ResourceDetailLoader.loadProjectDetail(
            projectId: project.projectId,
            gameRepository: gameRepository,
            resourceType: query
        ) else {
            return
        }

        // Set preloadedDetail first
        await MainActor.run {
            preloadedDetail = result.detail
        }

        // Wait for the main thread cycle before displaying the sheet
        await MainActor.run {
            // Display sheet only if preloadedDetail is not nil
            if preloadedDetail != nil {
                showGameResourceInstallSheet = true
            }
        }
    }

    // New: Detect if there is a new version (only in local mode)
    private func checkForUpdate() {
        guard let gameInfo = gameInfo,
              type == false,  // Only in local mode
              !isDisabled,  // If the resource is disabled, it does not participate in detecting updates
              !project.projectId.hasPrefix("local_") && !project.projectId.hasPrefix("file_")  // Exclude local file resources
        else {
            return
        }

        Task {
            let result = await ModUpdateChecker.checkForUpdate(
                project: project,
                gameInfo: gameInfo,
                resourceType: query
            )

            await MainActor.run {
                if result.hasUpdate {
                    addButtonState = .update
                } else {
                    addButtonState = .installed
                }
            }
        }
    }

    // New: Update scannedDetailIds after installation is complete (using hash)
    private func addToScannedDetailIds(hash: String? = nil) {
        // If there is a hash, use the hash; otherwise, do not add it yet
        // In actual use, you should obtain the hash and call this function after the download is completed
        if let hash = hash {
            scannedDetailIds.insert(hash)
        }
    }

    private func updateDisableState() {
        // Use currentFileName if it exists, otherwise use project.fileName
        let fileName = currentFileName ?? project.fileName
        isDisabled = ResourceEnableDisableManager.isDisabled(fileName: fileName)
        // Synchronously update the state exposed to the parent view
        isResourceDisabled = isDisabled
    }

    private func toggleDisableState() {
        guard let gameInfo = gameInfo,
            let resourceDir = AppPaths.resourceDirectory(
                for: query,
                gameName: gameInfo.gameName
            )
        else {
            Logger.shared.error("Failed to switch resource enablement status: Resource directory does not exist")
            return
        }

        // Use currentFileName if it exists, otherwise use project.fileName
        let fileName = currentFileName ?? project.fileName
        guard let fileName = fileName else {
            Logger.shared.error("Failed to switch resource enabled state: missing filename")
            return
        }

        do {
            let newFileName = try ResourceEnableDisableManager.toggleDisableState(
                fileName: fileName,
                resourceDir: resourceDir
            )
            // Update current filename and disabled status
            currentFileName = newFileName
            isDisabled = ResourceEnableDisableManager.isDisabled(fileName: newFileName)
            // Synchronously update the state exposed to the parent view
            isResourceDisabled = isDisabled

            // Notify external local resources that their enabled/disabled status has changed
            onToggleDisableState?(isDisabled)
        } catch {
            Logger.shared.error("Failed to switch resource enable status: \(error.localizedDescription)")
        }
    }
}

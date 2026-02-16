import SwiftUI
import UniformTypeIdentifiers
import SkinRenderKit

struct SkinToolDetailView: View {
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @Environment(\.dismiss)
    private var dismiss

    // Preloaded data (optional)
    private let preloadedSkinInfo: PlayerSkinService.PublicSkinInfo?
    private let preloadedProfile: MinecraftProfileResponse?

    @State private var currentModel: PlayerSkinService.PublicSkinInfo.SkinModel = .classic
    @State private var showingFileImporter = false
    @State private var operationInProgress = false
    @State private var selectedSkinData: Data?
    @State private var selectedSkinImage: NSImage?
    @State private var selectedSkinPath: String?
    @State private var showingSkinPreview = false
    @State private var selectedCapeId: String?
    @State private var selectedCapeImageURL: String?
    @State private var selectedCapeLocalPath: String?
    @State private var selectedCapeImage: NSImage?
    @State private var isCapeLoading: Bool = false
    @State private var capeLoadCompleted: Bool = false
    @State private var publicSkinInfo: PlayerSkinService.PublicSkinInfo?
    @State private var playerProfile: MinecraftProfileResponse?

    init(
        preloadedSkinInfo: PlayerSkinService.PublicSkinInfo? = nil,
        preloadedProfile: MinecraftProfileResponse? = nil
    ) {
        self.preloadedSkinInfo = preloadedSkinInfo
        self.preloadedProfile = preloadedProfile
    }

    @State private var hasChanges = false
    @State private var currentSkinRenderImage: NSImage?
    // Cache previous values ​​to avoid unnecessary calculations
    @State private var lastSelectedSkinData: Data?
    @State private var lastCurrentModel: PlayerSkinService.PublicSkinInfo.SkinModel = .classic
    @State private var lastSelectedCapeId: String?
    @State private var lastCurrentActiveCapeId: String?

    // Task reference management, used to cancel all asynchronous tasks during cleanup
    @State private var loadCapeTask: Task<Void, Never>?
    @State private var loadSkinImageTask: Task<Void, Never>?
    @State private var downloadCapeTask: Task<Void, Never>?
    @State private var resetSkinTask: Task<Void, Never>?
    @State private var applyChangesTask: Task<Void, Never>?

    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyContentView },
            footer: { footerView }
        )
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .onAppear {
            // Use preloaded data entirely
            guard let skinInfo = preloadedSkinInfo, let profile = preloadedProfile else {
                dismiss()
                return
            }
            publicSkinInfo = skinInfo
            playerProfile = profile
            currentModel = skinInfo.model
            selectedCapeId = PlayerSkinService.getActiveCapeId(from: profile)

            // Initialize loading state
            isCapeLoading = false
            capeLoadCompleted = false

            // Load current skin image
            loadCurrentSkinRenderImageIfNeeded()

            // Immediately load the currently active cloak (using high priority tasks)
            loadCapeTask?.cancel()
            loadCapeTask = Task<Void, Never>(priority: .userInitiated) {
                await loadCurrentActiveCapeIfNeeded(from: profile)
            }

            updateHasChanges()
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
    }

    private var headerView: some View {
        Text("Skin Manager").font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyContentView: some View {
        VStack(spacing: 24) {
            PlayerInfoSectionView(
                player: resolvedPlayer,
                currentModel: $currentModel
            )
            .onChange(of: currentModel) { _, _ in
                updateHasChanges()
            }

            SkinUploadSectionView(
                currentModel: $currentModel,
                showingFileImporter: $showingFileImporter,
                selectedSkinImage: $selectedSkinImage,
                selectedSkinPath: $selectedSkinPath,
                currentSkinRenderImage: $currentSkinRenderImage,
                selectedCapeLocalPath: $selectedCapeLocalPath,
                selectedCapeImage: $selectedCapeImage,
                selectedCapeImageURL: $selectedCapeImageURL,
                isCapeLoading: $isCapeLoading,
                capeLoadCompleted: $capeLoadCompleted,
                showingSkinPreview: $showingSkinPreview,
                onSkinDropped: handleSkinDroppedImage,
                onDrop: handleDrop
            )

            CapeSelectionView(
                playerProfile: playerProfile,
                selectedCapeId: $selectedCapeId,
                selectedCapeImageURL: $selectedCapeImageURL,
                selectedCapeImage: $selectedCapeImage
            ) { id, imageURL in
                loadCapeTask?.cancel()
                loadCapeTask = nil

                if let imageURL = imageURL, id != nil {
                    // Clear old images immediately when switching cloaks to avoid showing wrong preview images
                    // New images will be updated after the asynchronous download is complete
                    selectedCapeImage = nil
                    downloadCapeTask?.cancel()
                    downloadCapeTask = Task<Void, Never> {
                        await MainActor.run {
                            isCapeLoading = true
                            capeLoadCompleted = false
                        }
                        await downloadCapeTextureAndSetImage(from: imageURL)
                        await MainActor.run {
                            isCapeLoading = false
                            capeLoadCompleted = true
                        }
                    }
                } else {
                    selectedCapeLocalPath = nil
                    // Debug log: Deselecting cloak
                    // Logger.shared.info("[SkinToolDetailView] set selectedCapeImage = nil (unselect cape), id: \(id ?? "nil")")
                    selectedCapeImage = nil
                    // Completes immediately when deselecting a cape (since there are no capes to load)
                    capeLoadCompleted = true
                    isCapeLoading = false
                }
                updateHasChanges()
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()

            HStack(spacing: 12) {
                if resolvedPlayer?.isOnlineAccount == true {
                    Button("Reset Skin") { resetSkin() }.disabled(operationInProgress)
                }
                Button("Apply Changes") { applyChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(operationInProgress || !hasChanges)
            }
        }
    }

    private func handleSkinDroppedImage(_ image: NSImage) {
        // Convert NSImage to PNG Data
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            Logger.shared.error("Failed to convert dropped image to PNG data")
            return
        }

        // Validate PNG data
        guard data.isPNG else {
            Logger.shared.error("Converted data is not valid PNG format")
            return
        }

        selectedSkinData = data
        selectedSkinImage = image
        Task { @MainActor in
            let path = await Task.detached(priority: .userInitiated) {
                self.saveTempSkinFile(data: data)?.path
            }.value
            selectedSkinPath = path
            updateHasChanges()
        }

        Logger.shared.info("Skin image dropped and processed successfully. Model: \(currentModel.rawValue)")
    }

    private var resolvedPlayer: Player? { playerListViewModel.currentPlayer }

    /// When needing to access protected resources such as skins/cloaks, ensure that the player has loaded the authentication credentials (accessToken) from the Keychain
    private func playerWithCredentialIfNeeded(_ player: Player?) -> Player? {
        guard let p = player, p.isOnlineAccount else { return player }
        var copy = p
        if copy.credential == nil {
            if let c = PlayerDataManager().loadCredential(userId: p.id) {
                copy.credential = c
            }
        }
        return copy
    }

    private func updateHasChanges() {
        // Check if any relevant values ​​have changed
        let skinDataChanged = selectedSkinData != lastSelectedSkinData
        let modelChanged = currentModel != lastCurrentModel
        let capeIdChanged = selectedCapeId != lastSelectedCapeId
        let activeCapeIdChanged = currentActiveCapeId != lastCurrentActiveCapeId

        // If there are no changes, return directly
        if !skinDataChanged && !modelChanged && !capeIdChanged && !activeCapeIdChanged {
            return
        }

        // Update cached value
        lastSelectedSkinData = selectedSkinData
        lastCurrentModel = currentModel
        lastSelectedCapeId = selectedCapeId
        lastCurrentActiveCapeId = currentActiveCapeId

        let hasSkinChange = PlayerSkinService.hasSkinChanges(
            selectedSkinData: selectedSkinData,
            currentModel: currentModel,
            originalModel: originalModel
        )
        let hasCapeChange = PlayerSkinService.hasCapeChanges(
            selectedCapeId: selectedCapeId,
            currentActiveCapeId: currentActiveCapeId
        )

        hasChanges = hasSkinChange || hasCapeChange
    }

    private var currentActiveCapeId: String? {
        PlayerSkinService.getActiveCapeId(from: playerProfile)
    }

    private var originalModel: PlayerSkinService.PublicSkinInfo.SkinModel? {
        publicSkinInfo?.model
    }

    private func loadCurrentSkinRenderImageIfNeeded() {
        if selectedSkinImage != nil || selectedSkinPath != nil { return }
        guard let urlString = publicSkinInfo?.skinURL?.httpToHttps(), let url = URL(string: urlString) else { return }
        loadSkinImageTask?.cancel()
        loadSkinImageTask = Task<Void, Never> {
            do {
                let p = playerWithCredentialIfNeeded(resolvedPlayer)
                var headers: [String: String]?
                if let t = p?.authAccessToken, !t.isEmpty {
                    headers = ["Authorization": "Bearer \(t)"]
                } else {
                    headers = nil
                }
                let data = try await APIClient.get(url: url, headers: headers)
                guard !data.isEmpty, let image = NSImage(data: data) else { return }
                try Task.checkCancellation()
                await MainActor.run { self.currentSkinRenderImage = image }
            } catch is CancellationError {
                // The task was canceled and does not need to be processed
            } catch {
                Logger.shared.error("Failed to load current skin image for renderer: \(error)")
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }

            let urlForBackground = url
            Task { @MainActor in
                let data = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: urlForBackground)
                }.value
                urlForBackground.stopAccessingSecurityScopedResource()
                if let data = data {
                    processSkinData(data, filePath: urlForBackground.path)
                } else {
                    Logger.shared.error("Failed to read skin file")
                }
            }
        case .failure(let error):
            Logger.shared.error("File selection failed: \(error)")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data = data else { return }
            Task { @MainActor in
                let tempURL = await Task.detached(priority: .userInitiated) { () -> URL? in
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "temp_skin_\(UUID().uuidString).png"
                    let tempURL = tempDir.appendingPathComponent(fileName)
                    do {
                        try data.write(to: tempURL)
                        return tempURL
                    } catch {
                        Logger.shared.error("Failed to save temporary skin file: \(error)")
                        return nil
                    }
                }.value
                self.processSkinData(data, filePath: tempURL?.path)
            }
        }
        return true
    }

    private func processSkinData(_ data: Data, filePath: String? = nil) {
        guard data.isPNG else { return }
        selectedSkinData = data
        selectedSkinImage = NSImage(data: data)
        selectedSkinPath = filePath
        updateHasChanges()
    }

    /// Write temporary skin files in the background to avoid main thread data.write
    nonisolated private func saveTempSkinFile(data: Data) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "temp_skin_\(UUID().uuidString).png"
        let tempURL = tempDir.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            Logger.shared.error("Failed to save temporary skin file: \(error)")
            return nil
        }
    }

    private func clearSelectedSkin() {
        selectedSkinData = nil
        selectedSkinImage = nil
        selectedSkinPath = nil
        showingSkinPreview = false
        updateHasChanges()
    }

    private func resetSkin() {
        guard let resolved = resolvedPlayer else { return }
        let player = playerWithCredentialIfNeeded(resolved) ?? resolved

        operationInProgress = true
        resetSkinTask?.cancel()
        resetSkinTask = Task<Void, Never> {
            do {
                let success = await PlayerSkinService.resetSkinAndRefresh(player: player)
                try Task.checkCancellation()

                await MainActor.run {
                    operationInProgress = false
                    if success {
                        // After the reset is successful, close the view, reopen it externally and pass in new preloaded data
                        dismiss()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    operationInProgress = false
                }
            } catch {
                // Other errors, reset status
                await MainActor.run {
                    operationInProgress = false
                }
            }
        }
    }

    private func applyChanges() {
        guard let resolved = resolvedPlayer else { return }
        let player = playerWithCredentialIfNeeded(resolved) ?? resolved

        operationInProgress = true
        applyChangesTask?.cancel()
        applyChangesTask = Task<Void, Never> {
            do {
                let skinSuccess = await handleSkinChanges(player: player)
                try Task.checkCancellation()
                let capeSuccess = await handleCapeChanges(player: player)
                try Task.checkCancellation()

                await MainActor.run {
                    operationInProgress = false
                    if skinSuccess && capeSuccess {
                        dismiss()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    operationInProgress = false
                }
            } catch {
                // Other errors, reset status
                await MainActor.run {
                    operationInProgress = false
                }
            }
        }
    }

    private func handleSkinChanges(player: Player) async -> Bool {
        do {
            try Task.checkCancellation()

            if let skinData = selectedSkinData {
                let result = await PlayerSkinService.uploadSkinAndRefresh(
                    imageData: skinData,
                    model: currentModel,
                    player: player
                )
                try Task.checkCancellation()
                if result {
                    Logger.shared.info("Skin upload successful with model: \(currentModel.rawValue)")
                } else {
                    Logger.shared.error("Skin upload failed")
                }
                return result
            } else if let original = originalModel, currentModel != original {
                if let currentSkinInfo = publicSkinInfo, let skinURL = currentSkinInfo.skinURL {
                    let result = await uploadCurrentSkinWithNewModel(skinURL: skinURL, player: player)
                    try Task.checkCancellation()
                    return result
                } else {
                    return false
                }
            } else if originalModel == nil && currentModel != .classic {
                return false
            }
            return true // No skin changes needed
        } catch is CancellationError {
            return false
        } catch {
            Logger.shared.error("Skin changes error: \(error)")
            return false
        }
    }

    private func handleCapeChanges(player: Player) async -> Bool {
        do {
            try Task.checkCancellation()

            if selectedCapeId != currentActiveCapeId {
                try Task.checkCancellation()
                if let capeId = selectedCapeId {
                    let result = await PlayerSkinService.showCape(capeId: capeId, player: player)
                    try Task.checkCancellation()
                    if result {
                        // After success, refresh the player profile to ensure that the currently activated cloak ID is consistent with the server
                        if let newProfile = await PlayerSkinService.fetchPlayerProfile(player: player) {
                            await MainActor.run {
                                self.playerProfile = newProfile
                                self.selectedCapeId = PlayerSkinService.getActiveCapeId(from: newProfile)
                                self.updateHasChanges()
                            }
                        }
                    }
                    return result
                } else {
                    let result = await PlayerSkinService.hideCape(player: player)
                    try Task.checkCancellation()
                    if result {
                        if let newProfile = await PlayerSkinService.fetchPlayerProfile(player: player) {
                            await MainActor.run {
                                self.playerProfile = newProfile
                                self.selectedCapeId = PlayerSkinService.getActiveCapeId(from: newProfile)
                                self.updateHasChanges()
                            }
                        }
                    }
                    return result
                }
            }
            return true // No cape changes needed
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }

    private func uploadCurrentSkinWithNewModel(skinURL: String, player: Player) async -> Bool {
        do {
            try Task.checkCancellation()
            let p = playerWithCredentialIfNeeded(player) ?? player

            // Convert HTTP URLs to HTTPS to comply with ATS policies
            let httpsURL = skinURL.httpToHttps()

            guard let url = URL(string: httpsURL) else {
                return false
            }
            var headers: [String: String]?
            if !p.authAccessToken.isEmpty {
                headers = ["Authorization": "Bearer \(p.authAccessToken)"]
            } else {
                headers = nil
            }
            let data = try await APIClient.get(url: url, headers: headers)
            try Task.checkCancellation()

            let result = await PlayerSkinService.uploadSkin(
                imageData: data,
                model: currentModel,
                player: p
            )
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            return false
        } catch {
            Logger.shared.error("Failed to re-upload skin with new model: \(error)")
            return false
        }
    }
}

extension Data {
    var isPNG: Bool {
        self.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

// MARK: - Cape Download Extension
extension SkinToolDetailView {
    /// Loads the currently active cloak (if one exists)
    private func loadCurrentActiveCapeIfNeeded(from profile: MinecraftProfileResponse) async {
        do {
            try Task.checkCancellation()

            // If the user has manually selected a different cloak than the currently active cloak, the "currently active cloak" will no longer be loaded to avoid overwriting the preview
            if let manualSelectedId = selectedCapeId,
               let activeId = PlayerSkinService.getActiveCapeId(from: profile),
               manualSelectedId != activeId {
                return
            }

            // Check capeURL in publicSkinInfo first
            if let capeURL = publicSkinInfo?.capeURL, !capeURL.isEmpty {
                await MainActor.run {
                    selectedCapeImageURL = capeURL
                    isCapeLoading = true
                    capeLoadCompleted = false
                }
                try Task.checkCancellation()
                await downloadCapeTextureAndSetImage(from: capeURL)
                try Task.checkCancellation()
                await MainActor.run {
                    isCapeLoading = false
                    capeLoadCompleted = true
                }
                return
            }

            try Task.checkCancellation()

            // Otherwise look for the active cloak from profile
            guard let activeCapeId = PlayerSkinService.getActiveCapeId(from: profile) else {
                await MainActor.run {
                    selectedCapeImageURL = nil
                    selectedCapeLocalPath = nil
                    selectedCapeImage = nil
                    isCapeLoading = false
                    capeLoadCompleted = true  // No cape, skin can be rendered immediately
                }
                return
            }

            try Task.checkCancellation()

            guard let capes = profile.capes, !capes.isEmpty else {
                await MainActor.run {
                    selectedCapeImageURL = nil
                    selectedCapeLocalPath = nil
                    selectedCapeImage = nil
                    isCapeLoading = false
                    capeLoadCompleted = true  // No cape, skin can be rendered immediately
                }
                return
            }

            try Task.checkCancellation()

            guard let activeCape = capes.first(where: { $0.id == activeCapeId && $0.state == "ACTIVE" }) else {
                await MainActor.run {
                    selectedCapeImageURL = nil
                    selectedCapeLocalPath = nil
                    selectedCapeImage = nil
                    isCapeLoading = false
                    capeLoadCompleted = true  // There is no active cape and the skin can be rendered immediately
                }
                return
            }

            try Task.checkCancellation()

            // There is a cloak that needs to be loaded, set the loading status
            await MainActor.run {
                selectedCapeImageURL = activeCape.url
                isCapeLoading = true
                capeLoadCompleted = false
            }
            try Task.checkCancellation()
            await downloadCapeTextureAndSetImage(from: activeCape.url)
            try Task.checkCancellation()
            await MainActor.run {
                isCapeLoading = false
                capeLoadCompleted = true
            }
        } catch is CancellationError {
            // The task is canceled and the status is reset
            await MainActor.run {
                isCapeLoading = false
                capeLoadCompleted = false
            }
        } catch {
            // Other errors, reset state and log
            Logger.shared.error("Failed to load current active cape: \(error)")
            await MainActor.run {
                isCapeLoading = false
                capeLoadCompleted = false
            }
        }
    }

    fileprivate func downloadCapeTextureIfNeeded(from urlString: String) async {
        if let current = selectedCapeImageURL, current == urlString, selectedCapeLocalPath != nil {
            return
        }
        // Verify URL format (but do not preserve URL objects, saving memory)
        guard URL(string: urlString.httpToHttps()) != nil else {
            return
        }
        do {
            // Download files using DownloadManager (all optimizations included)
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cape_\(UUID().uuidString).png")
            _ = try await DownloadManager.downloadFile(
                urlString: urlString.httpToHttps(),
                destinationURL: tempFile,
                expectedSha1: nil
            )
            await MainActor.run {
                if selectedCapeImageURL == urlString {
                    selectedCapeLocalPath = tempFile.path
                }
            }
        } catch {
            Logger.shared.error("Cape download error: \(error)")
        }
    }

    /// Download the cape texture and set the image
    private func downloadCapeTextureAndSetImage(from urlString: String) async {
        // Check if the same URL has already been downloaded
        if let currentURL = selectedCapeImageURL,
           currentURL == urlString,
           let currentPath = selectedCapeLocalPath,
           FileManager.default.fileExists(atPath: currentPath),
           let cachedImage = NSImage(contentsOfFile: currentPath) {
            try? Task.checkCancellation()
            await MainActor.run {
                selectedCapeImage = cachedImage
            }
            return
        }

        // Verify URL format
        guard let url = URL(string: urlString.httpToHttps()) else {
            await MainActor.run {
                selectedCapeImage = nil
            }
            return
        }

        do {
            let p = playerWithCredentialIfNeeded(resolvedPlayer)
            var headers: [String: String]?
            if let t = p?.authAccessToken, !t.isEmpty {
                headers = ["Authorization": "Bearer \(t)"]
            } else {
                headers = nil
            }
            let data = try await APIClient.get(url: url, headers: headers)
            try Task.checkCancellation()

            guard !data.isEmpty, let image = NSImage(data: data) else {
                await MainActor.run {
                    selectedCapeImage = nil
                }
                return
            }

            try Task.checkCancellation()

            // Update UI immediately without waiting for file to be saved
            await MainActor.run {
                // Check if the URL still matches (prevents users from switching quickly)
                if selectedCapeImageURL == urlString {
                    selectedCapeImage = image
                }
            }

            try Task.checkCancellation()

            // Asynchronously save to temporary file (without blocking UI updates)
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cape_\(UUID().uuidString).png")
            do {
                try data.write(to: tempFile)
                try Task.checkCancellation()
                await MainActor.run {
                    if selectedCapeImageURL == urlString {
                        selectedCapeLocalPath = tempFile.path
                    }
                }
            } catch is CancellationError {
                // If the task is canceled, delete the file just created
                try? FileManager.default.removeItem(at: tempFile)
            } catch {
                Logger.shared.error("Failed to save cape to temp file: \(error)")
            }
        } catch is CancellationError {
            // The task was canceled and does not need to be processed
        } catch {
            Logger.shared.error("Cape download error: \(error.localizedDescription)")
        }
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Cancel all running asynchronous tasks
        loadCapeTask?.cancel()
        loadSkinImageTask?.cancel()
        downloadCapeTask?.cancel()
        resetSkinTask?.cancel()
        applyChangesTask?.cancel()

        // Clean all Task references
        loadCapeTask = nil
        loadSkinImageTask = nil
        downloadCapeTask = nil
        resetSkinTask = nil
        applyChangesTask = nil

        // Delete temporary files
        deleteTemporaryFiles()

        // Clear selected skin data
        selectedSkinData = nil
        selectedSkinImage = nil
        selectedSkinPath = nil
        showingSkinPreview = false
        // Clean cloak data
        selectedCapeId = nil
        selectedCapeImageURL = nil
        selectedCapeLocalPath = nil
        selectedCapeImage = nil
        isCapeLoading = false
        capeLoadCompleted = false
        // Clean loaded data
        publicSkinInfo = nil
        playerProfile = nil
        currentSkinRenderImage = nil
        // reset state
        currentModel = .classic
        hasChanges = false
        operationInProgress = false
        // Clear cached values
        lastSelectedSkinData = nil
        lastCurrentModel = .classic
        lastSelectedCapeId = nil
        lastCurrentActiveCapeId = nil
    }

    /// Delete temporary files created
    private func deleteTemporaryFiles() {
        let fileManager = FileManager.default

        // Delete temporary skin files
        if let skinPath = selectedSkinPath, !skinPath.isEmpty {
            let skinURL = URL(fileURLWithPath: skinPath)
            // Only delete temporary files in the temporary directory
            if skinURL.path.hasPrefix(fileManager.temporaryDirectory.path) {
                do {
                    try fileManager.removeItem(at: skinURL)
                    Logger.shared.info("Deleted temporary skin file: \(skinPath)")
                } catch {
                    Logger.shared.warning("Failed to delete temporary skin file: \(error.localizedDescription)")
                }
            }
        }

        // Delete temporary cloak files
        if let capePath = selectedCapeLocalPath, !capePath.isEmpty {
            let capeURL = URL(fileURLWithPath: capePath)
            // Only delete temporary files in the temporary directory
            if capeURL.path.hasPrefix(fileManager.temporaryDirectory.path) {
                do {
                    try fileManager.removeItem(at: capeURL)
                } catch {
                    Logger.shared.warning("Failed to delete temporary cape file: \(error.localizedDescription)")
                }
            }
        }
    }
}

import SwiftUI

/// Content area toolbar content
public struct ContentToolbarView: ToolbarContent {
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @State private var showingAddPlayerSheet = false
    @State private var playerName = ""
    @State private var isPlayerNameValid = false
    @State private var showPlayerAlert = false
    @State private var showingGameForm = false
    @EnvironmentObject var gameRepository: GameRepository
    @State private var showEditSkin = false
    @State private var isLoadingSkin = false
    @State private var preloadedSkinInfo: PlayerSkinService.PublicSkinInfo?
    @State private var preloadedProfile: MinecraftProfileResponse?

    // MARK: - Startup Info State
    @State private var showStartupInfo = false
    @State private var hasAnnouncement = false
    @State private var announcementData: AnnouncementData?
    @State private var hasCheckedAnnouncement = false

    // MARK: - Computed Properties

    /// Current player (calculated attribute to avoid repeated access)
    private var currentPlayer: Player? {
        playerListViewModel.currentPlayer
    }

    /// Whether it is an online account (calculated attribute)
    private var isCurrentPlayerOnline: Bool {
        currentPlayer?.isOnlineAccount ?? false
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if currentPlayer == nil {
                    showPlayerAlert = true
                } else {
                    showingGameForm.toggle()
                }
            } label: {
                Label("Add Game", systemImage: "plus")
            }
            .help("Add Game")
            .task {
                // Delay checking of announcements without blocking initial rendering
                guard !hasCheckedAnnouncement else { return }
                hasCheckedAnnouncement = true
                // Use low-priority tasks to execute in the background without blocking UI rendering
                Task(priority: .utility) {
                    await checkAnnouncement()
                }
            }
            .sheet(isPresented: $showingGameForm) {
                GameFormView()
                    .environmentObject(gameRepository)
                    .environmentObject(playerListViewModel)
                    .presentationBackgroundInteraction(.automatic)
            }
            Spacer()
            // add player button
            Button {
                playerName = ""
                isPlayerNameValid = false
                showingAddPlayerSheet = true
            } label: {
                Label("Add Player", systemImage: "person.badge.plus")
            }
            .help("Add Player")
            .sheet(isPresented: $showingAddPlayerSheet) {
                AddPlayerSheetView(
                    playerName: $playerName,
                    isPlayerNameValid: $isPlayerNameValid,
                    onAdd: {
                        if playerListViewModel.addPlayer(name: playerName) {
                            Logger.shared.debug("Player \(playerName) was added successfully (via ViewModel)")
                        } else {
                            Logger.shared.debug("Failed to add player \(playerName) (via ViewModel)")
                        }
                        isPlayerNameValid = true
                        showingAddPlayerSheet = false
                    },
                    onCancel: {
                        playerName = ""
                        isPlayerNameValid = false

                        showingAddPlayerSheet = false
                        // Delay cleaning of authentication status to avoid affecting the dialog box closing animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            MinecraftAuthService.shared.clearAuthenticationData()
                        }
                    },
                    onLogin: { profile in
                        // Processing genuine login successfully, using Minecraft user profile
                        Logger.shared.debug("Genuine login successful, user: \(profile.name)")
                        // Add genuine players
                        _ = playerListViewModel.addOnlinePlayer(profile: profile)

                        // Set up a genuine account and add a mark
                        PremiumAccountFlagManager.shared.setPremiumAccountAdded()

                        showingAddPlayerSheet = false
                        // Delay cleaning of authentication status so users can see the success status
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            MinecraftAuthService.shared.clearAuthenticationData()
                        }
                    },

                    playerListViewModel: playerListViewModel
                )
            }
            .alert(isPresented: $showPlayerAlert) {
                Alert(
                    title: Text("No Players"),
                    message: Text("No player information. Please add player information first before adding games"),
                    dismissButton: .default(Text("Confirm"))
                )
            }

            // Skin management button - only displayed on online accounts
            if isCurrentPlayerOnline {
                Button {
                    Task {
                        await openSkinManager()
                    }
                } label: {
                    if isLoadingSkin {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Skin", systemImage: "tshirt")
                    }
                }
                .help("Skin")
                .disabled(isLoadingSkin)
                .sheet(isPresented: $showEditSkin) {
                    SkinToolDetailView(
                        preloadedSkinInfo: preloadedSkinInfo,
                        preloadedProfile: preloadedProfile
                    )
                    .onDisappear {
                        // Clean preloaded data
                        preloadedSkinInfo = nil
                        preloadedProfile = nil
                    }
                }
            }

            // Launch information button - only shown if there is an announcement
            if hasAnnouncement, let announcement = announcementData {
                Button {
                    showStartupInfo = true
                } label: {
                    Label(announcement.title, systemImage: "bell.badge")
                        .labelStyle(.iconOnly)
                }
                .help(announcement.title)
                .sheet(isPresented: $showStartupInfo) {
                    StartupInfoSheetView(announcementData: announcementData)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Open the skin manager (load data first, then display the sheet)
    private func openSkinManager() async {
        guard let player = currentPlayer else { return }

        await MainActor.run {
            isLoadingSkin = true
        }

        // If it is an offline account, use it directly without refreshing the token
        guard player.isOnlineAccount else {
            // Preload skin data
            async let skinInfo = PlayerSkinService.fetchCurrentPlayerSkinFromServices(player: player)
            async let profile = PlayerSkinService.fetchPlayerProfile(player: player)
            let (loadedSkinInfo, loadedProfile) = await (skinInfo, profile)

            await MainActor.run {
                preloadedSkinInfo = loadedSkinInfo
                preloadedProfile = loadedProfile
                isLoadingSkin = false
                showEditSkin = true
            }
            return
        }

        Logger.shared.info("Verify player \(player.name)'s Token before opening the skin manager")

        // Load authentication credentials on demand from Keychain (only for current player, avoid reading all accounts at once)
        var playerWithCredential = player
        if playerWithCredential.credential == nil {
            let dataManager = PlayerDataManager()
            if let credential = dataManager.loadCredential(userId: playerWithCredential.id) {
                playerWithCredential.credential = credential
            }
        }

        // Verify using the loaded/updated player object and try to refresh the token
        let authService = MinecraftAuthService.shared
        let validatedPlayer: Player
        do {
            validatedPlayer = try await authService.validateAndRefreshPlayerTokenThrowing(for: playerWithCredential)

            // If the Token is updated, it needs to be saved to PlayerDataManager
            if validatedPlayer.authAccessToken != player.authAccessToken {
                Logger.shared.info("Player \(player.name)'s Token has been updated and saved to the data manager")
                let dataManager = PlayerDataManager()
                let success = dataManager.updatePlayerSilently(validatedPlayer)
                if success {
                    Logger.shared.debug("Token information in player data manager has been updated")
                    // Synchronously update the player list in memory (to avoid using old tokens at next startup)
                    NotificationCenter.default.post(
                        name: PlayerSkinService.playerUpdatedNotification,
                        object: nil,
                        userInfo: ["updatedPlayer": validatedPlayer]
                    )
                }
            }
        } catch {
            Logger.shared.error("Failed to refresh Token: \(error.localizedDescription)")
            // When token refresh fails, still try to use the original token to load skin data
            validatedPlayer = playerWithCredential
        }

        // Preload skin data (using authenticated player object)
        async let skinInfo = PlayerSkinService.fetchCurrentPlayerSkinFromServices(player: validatedPlayer)
        async let profile = PlayerSkinService.fetchPlayerProfile(player: validatedPlayer)
        let (loadedSkinInfo, loadedProfile) = await (skinInfo, profile)

        await MainActor.run {
            preloadedSkinInfo = loadedSkinInfo
            preloadedProfile = loadedProfile
            isLoadingSkin = false
            showEditSkin = true
        }
    }

    /// Check if there is an announcement
    /// Only called once at startup
    private func checkAnnouncement() async {
        let version = Bundle.main.appVersion
        let language = LanguageManager.shared.selectedLanguage.isEmpty
            ? LanguageManager.getDefaultLanguage()
            : LanguageManager.shared.selectedLanguage

        do {
            let data = try await GitHubService.shared.fetchAnnouncement(
                version: version,
                language: language
            )

            await MainActor.run {
                if let data = data {
                    self.hasAnnouncement = true
                    self.announcementData = data
                } else {
                    self.hasAnnouncement = false
                    self.announcementData = nil
                }
            }
        } catch {
            await MainActor.run {
                self.hasAnnouncement = false
                self.announcementData = nil
            }
        }
    }
}

import SwiftUI

/// Content area toolbar content
public struct ContentToolbarView: ToolbarContent {
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @State private var showPlayerAlert = false
    @State private var showingGameForm = false
    @EnvironmentObject var gameRepository: GameRepository

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
            .alert(isPresented: $showPlayerAlert) {
                Alert(
                    title: Text("No Players"),
                    message: Text("No player information. Please add player information first before adding games"),
                    dismissButton: .default(Text("Confirm"))
                )
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

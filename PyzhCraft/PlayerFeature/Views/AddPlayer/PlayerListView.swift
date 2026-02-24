import SwiftUI

/// Player state manager (single case)
class PlayerStatusManager: ObservableObject {
    static let shared = PlayerStatusManager()

    @Published private var statusCache: [String: PlayerStatus] = [:]
    private var checkTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Get player status
    func getStatus(for player: Player) -> PlayerStatus {
        statusCache[player.id] ?? .offline
    }

    /// Check player status
    func checkStatus(for player: Player) {
        // Cancel previous task
        checkTasks[player.id]?.cancel()

        // If it is an offline account, set it directly to offline status (yellow)
        if !player.isOnlineAccount {
            statusCache[player.id] = .offline
            return
        }

        // Genuine account: If the token is empty, it is considered expired (red)
        if player.authAccessToken.isEmpty {
            statusCache[player.id] = .expired
            return
        }

        // For genuine accounts, check asynchronously whether the token has expired
        let task = Task {
            let authService = MinecraftAuthService.shared
            let isExpired = await authService.isTokenExpiredBasedOnTime(for: player)

            await MainActor.run {
                if isExpired {
                    statusCache[player.id] = .expired
                } else {
                    statusCache[player.id] = .valid
                }
            }
        }

        checkTasks[player.id] = task
    }

    /// Player status enum
    enum PlayerStatus {
        case expired,
             valid,
             offline

        /// Get the icon name corresponding to the status
        var iconName: String {
            switch self {
            case .expired: "xmark.seal.fill"
            case .valid: "checkmark.seal.fill"
            case .offline: "checkmark.seal.fill"
            }
        }

        /// Get the color corresponding to the status
        var color: Color {
            switch self {
            case .expired: .red
            case .valid: .green
            case .offline: .yellow
            }
        }
    }

    /// Get the icon name corresponding to the player status
    func getStatusIconName(for player: Player) -> String {
        getStatus(for: player).iconName
    }

    /// Get the color corresponding to the player status
    func getStatusColor(for player: Player) -> Color {
        getStatus(for: player).color
    }
}

/// View showing player list
struct PlayerListView: View {
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @Environment(\.dismiss)
    var dismiss
    @State private var playerToDelete: Player?
    @State private var showDeleteAlert = false
    @State private var showingPlayerListPopover = false

    var body: some View {
        Button {
            showingPlayerListPopover.toggle()
        } label: {
            PlayerSelectorLabel(selectedPlayer: playerListViewModel.currentPlayer)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showingPlayerListPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(playerListViewModel.players) {
                    PlayerListItemView(player: $0, playerListViewModel: playerListViewModel, playerToDelete: $playerToDelete, showDeleteAlert: $showDeleteAlert, showingPlayerListPopover: $showingPlayerListPopover)
                }
            }
        }
        .confirmationDialog(
            "Remove Player",
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Remove Player", role: .destructive) {
                if let player = playerToDelete {
                    _ = playerListViewModel.deletePlayer(byID: player.id)
                }
                playerToDelete = nil
            }
            .keyboardShortcut(.defaultAction)

            Button("Cancel", role: .cancel) {
                playerToDelete = nil
            }
        } message: {
            Text("Are you sure you want to remove \(playerToDelete?.name ?? "")?")
        }
    }
}

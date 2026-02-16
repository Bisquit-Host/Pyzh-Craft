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
                    statusCache[player.id] = .expired  // Red: token expired
                } else {
                    statusCache[player.id] = .valid    // Green: token is valid
                }
            }
        }

        checkTasks[player.id] = task
    }

    /// Player status enum
    enum PlayerStatus {
        case expired    // Red: User expired (genuine)
        case valid      // Green: normal (genuine)
        case offline    // Yellow: offline

        /// Get the icon name corresponding to the status
        var iconName: String {
            switch self {
            case .expired:
                return "xmark.seal.fill"
            case .valid:
                return "checkmark.seal.fill"
            case .offline:
                return "checkmark.seal.fill"
            }
        }

        /// Get the color corresponding to the status
        var color: Color {
            switch self {
            case .expired:
                return .red
            case .valid:
                return .green
            case .offline:
                return .yellow
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
                ForEach(playerListViewModel.players) { player in
                    PlayerListItemView(player: player, playerListViewModel: playerListViewModel, playerToDelete: $playerToDelete, showDeleteAlert: $showDeleteAlert, showingPlayerListPopover: $showingPlayerListPopover)
                }
            }
//            .frame(width: 200)
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
            }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                playerToDelete = nil
            }
        } message: {
            Text(String(format: String(localized: "Are you sure you want to remove %@?"), playerToDelete?.name ?? ""))
        }
    }
}

private struct PlayerSelectorLabel: View {
    let selectedPlayer: Player?
    @StateObject private var statusManager = PlayerStatusManager.shared

    var body: some View {
        if let selectedPlayer = selectedPlayer {
            HStack(spacing: 8) {
                PlayerAvatarView(player: selectedPlayer, size: 32)
                Text(selectedPlayer.name)
                    .foregroundColor(.primary)
                    .font(.system(size: 13).bold())
                    .lineLimit(1)

//                Spacer()
//
//                // status indicator (right aligned)
//                Image(systemName: statusManager.getStatusIconName(for: selectedPlayer))
//                    .font(.system(size: 12))
//                    .foregroundColor(statusManager.getStatusColor(for: selectedPlayer))
            }
            .onAppear {
                statusManager.checkStatus(for: selectedPlayer)
            }
        } else {
            EmptyView()
        }
    }
}

// list item view
private struct PlayerListItemView: View {
    let player: Player
    let playerListViewModel: PlayerListViewModel
    @Binding var playerToDelete: Player?
    @Binding var showDeleteAlert: Bool
    @Binding var showingPlayerListPopover: Bool
    @StateObject private var statusManager = PlayerStatusManager.shared

    var body: some View {
        HStack {
//            //Status indicator (leftmost)
//            Image(systemName: statusManager.getStatusIconName(for: player))
//                .font(.system(size: 12))
//                .foregroundColor(statusManager.getStatusColor(for: player))
//                .frame(width: 20)

            Button {
                playerListViewModel.setCurrentPlayer(byID: player.id)
                showingPlayerListPopover = false
            } label: {
                PlayerAvatarView(player: player, size: 36)
                Text(player.name)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 64)
            Button {
                playerToDelete = player
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash.fill")
                    .help("Remove Player")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .onAppear {
            statusManager.checkStatus(for: player)
        }
    }
}

// PlayerAvatarView struct definition moved here
private struct PlayerAvatarView: View {
    let player: Player
    var size: CGFloat

    var body: some View {
        MinecraftSkinUtils(type: player.isOnlineAccount ? .url : .asset, src: player.avatarName, size: size)
            .id(player.id)
            .id(player.avatarName)
    }
}

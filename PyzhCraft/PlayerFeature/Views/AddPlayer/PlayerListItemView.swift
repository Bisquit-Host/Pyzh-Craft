import SwiftUI

struct PlayerListItemView: View {
    let player: Player
    let playerListViewModel: PlayerListViewModel
    @Binding var playerToDelete: Player?
    @Binding var showDeleteAlert: Bool
    @Binding var showingPlayerListPopover: Bool
    @StateObject private var statusManager = PlayerStatusManager.shared

    var body: some View {
        HStack {
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

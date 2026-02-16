import SwiftUI
import Combine

struct GameHeaderListRow: View {
    let game: GameVersionInfo
    let cacheInfo: CacheInfo
    let query: String
    let onImport: () -> Void
    var onIconTap: (() -> Void)?

    @State private var refreshTrigger = UUID()
    @State private var cancellable: AnyCancellable?

    var body: some View {
        HStack {
            gameIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(game.gameName)
                        .font(.title)
                        .bold()
                        .truncationMode(.tail)
                        .lineLimit(1)
                        .frame(minWidth: 0, maxWidth: 200)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack {
                        Label("\(cacheInfo.fileCount)", systemImage: "text.document")
                        Divider().frame(height: 16)
                        Label(cacheInfo.formattedSize, systemImage: "externaldrive")
                    }
                    .foregroundStyle(.secondary)
                    .font(.headline)
                    .padding(.leading, 6)
                }

                HStack(spacing: 8) {
                    Label(game.gameVersion, systemImage: "gamecontroller.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Divider().frame(height: 14)
                    Label(
                        game.modVersion.isEmpty
                            ? game.modLoader
                            : "\(game.modLoader)-\(game.modVersion)",
                        systemImage: "puzzlepiece.extension.fill"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    Divider().frame(height: 14)
                    Label(
                        game.lastPlayed.formatted(
                            .relative(presentation: .named)
                        ),
                        systemImage: "clock.fill"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                importButton
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(
            EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8)
        )
    }

    /// Icon file URL (the path is fixed; refresh only relies on notifications to trigger .id reconstruction)
    private var iconURL: URL {
        profileDir.appendingPathComponent(game.gameIcon)
    }

    private var gameIcon: some View {
        Group {
            if FileManager.default.fileExists(atPath: profileDir.appendingPathComponent(game.gameIcon).path) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.regular)
                            .frame(width: 80, height: 80)
                    case .success(let image):
                        styledIcon(image, size: 80)
                    case .failure:
                        defaultIcon
                    @unknown default:
                        defaultIcon
                    }
                }
                // Extra layer of insurance: force AsyncImage rebuild even if URL splicing/caching does not behave as expected
                .id(refreshTrigger)
            } else {
                defaultIcon
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onIconTap?()
        }
        .onAppear {
            // Listen for icon refresh notifications
            cancellable = IconRefreshNotifier.shared.refreshPublisher
                .sink { refreshedGameName in
                    // Refresh if the notification's game name matches, or if the notification is nil (refresh all)
                    if refreshedGameName == nil || refreshedGameName == game.gameName {
                        refreshTrigger = UUID()
                    }
                }
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }

    private var profileDir: URL {
        AppPaths.profileDirectory(gameName: game.gameName)
    }

    private var defaultIcon: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
            .resizable()
            .interpolation(.none)
            .frame(width: 80, height: 80)
            .cornerRadius(16)
    }

    @ViewBuilder
    private func styledIcon(_ image: Image, size: Int) -> some View {
        let padding: CGFloat = CGFloat(size) * 0.125 // padding is 12.5% ​​of size (10 at 80)
        let innerSize = CGFloat(size) - padding * 2
        let innerCornerRadius = innerSize * 0.2 // The inner fillet is 20% of the inner size
        let outerCornerRadius = CGFloat(size) * 0.2 // The outer fillet is 20% of the outer size

        image
            .resizable()
            .interpolation(.none)
            .scaledToFill()
            .frame(width: innerSize, height: innerSize)
            .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
            .padding(padding)
            .frame(width: CGFloat(size), height: CGFloat(size))
            .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
    }

    private var importButton: some View {
        LocalResourceInstaller.ImportButton(
            query: query,
            gameName: game.gameName
        ) { onImport() }
    }
}

import SwiftUI

// MARK: - Main view of archived information
struct SaveInfoView: View {
    let gameId: String
    let gameName: String
    @StateObject private var manager: SaveInfoManager
    
    init(gameId: String, gameName: String) {
        self.gameId = gameId
        self.gameName = gameName
        _manager = StateObject(wrappedValue: SaveInfoManager(gameName: gameName))
    }
    
    var body: some View {
        VStack {
            // World information area (only existing types are displayed)
            if manager.hasWorldsType {
                WorldInfoSectionView(
                    worlds: manager.worlds,
                    isLoading: manager.isLoadingWorlds,
                    gameName: gameName
                )
            }
            
            // Screenshot information area (only existing types are displayed)
            if manager.hasScreenshotsType {
                ScreenshotSectionView(
                    screenshots: manager.screenshots,
                    isLoading: manager.isLoadingScreenshots,
                    gameName: gameName
                )
            }
            
            // Server address area (always shown, even if no server is detected)
            if manager.hasServersType {
                ServerAddressSectionView(
                    servers: manager.servers,
                    isLoading: manager.isLoadingServers,
                    gameName: gameName
                ) {
                    Task {
                        await manager.loadData()
                    }
                }
            }
            
            // Litematica projected file area (only existing types are shown)
            if manager.hasLitematicaType {
                LitematicaSectionView(
                    litematicaFiles: manager.litematicaFiles,
                    isLoading: manager.isLoadingLitematica,
                    gameName: gameName
                )
            }
            
            // Log information area (only existing types are displayed)
            if manager.hasLogsType {
                LogSectionView(
                    logs: manager.logs,
                    isLoading: manager.isLoadingLogs
                )
            }
            
            // Show empty status when no information type is available
            if !manager.isLoading && !manager.hasWorldsType && !manager.hasScreenshotsType && !manager.hasServersType && !manager.hasLitematicaType && !manager.hasLogsType {
                Text("No information available to display")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .onChange(of: gameId) { _, _ in
            Task {
                await manager.loadData()
            }
        }
        .task {
            await manager.loadData()
        }
        .onDisappear {
            manager.clearCache()
        }
    }
}

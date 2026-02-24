import SwiftUI
import UserNotifications

@main
struct PyzhCraftApp: App {
    // MARK: - StateObjects
    @StateObject var playerListViewModel = PlayerListViewModel()
    @StateObject var gameRepository = GameRepository()
    @StateObject var gameLaunchUseCase = GameLaunchUseCase()
    @StateObject private var globalErrorHandler = GlobalErrorHandler.shared
    @StateObject private var sparkleUpdateService = SparkleUpdateService.shared
    @StateObject var generalSettingsManager = GeneralSettingsManager.shared
    @StateObject var themeManager = ThemeManager.shared
    @StateObject private var skinSelectionStore = SkinSelectionStore()
    
    // MARK: - Notification Delegate
    private let notificationCenterDelegate = NotificationCenterDelegate()
    
    init() {
        // Set up the notification center proxy to ensure that Banner can also be displayed in the foreground
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate
        
        Task {
            await NotificationManager.requestAuthorizationIfNeeded()
        }
    }
    
    // MARK: - Body
    var body: some Scene {
        
        WindowGroup {
            MainView()
                .environment(\.appLogger, Logger.shared)
                .environmentObject(playerListViewModel)
                .environmentObject(gameRepository)
                .environmentObject(gameLaunchUseCase)
                .environmentObject(sparkleUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(skinSelectionStore)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
                .windowOpener()
                .onAppear {
                    // Clear all window data when app starts
                    WindowDataStore.shared.cleanup(for: .aiChat)
                    WindowDataStore.shared.cleanup(for: .skinPreview)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .conditionalRestorationBehavior()
        .commands {
            
            CommandGroup(after: .appInfo) {
                Button("Check for Updates", action: sparkleUpdateService.checkForUpdatesWithUI)
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("Open Log", action: Logger.shared.openLogFile)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Divider()
                
                Link("GitHub", destination: URLConfig.API.GitHub.repositoryURL())
                
                Button("Contributors") {
                    WindowManager.shared.openWindow(id: .contributors)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("Acknowledgements") {
                    WindowManager.shared.openWindow(id: .acknowledgements)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Link("View License", destination: URLConfig.API.GitHub.licenseWebPage())
                    .keyboardShortcut("l", modifiers: [.command, .option])
                
                Divider()
                
                Button("AI Assistant", action: AIChatManager.shared.openChatWindow)
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
        }
        
        Settings {
            SettingsView()
                .environmentObject(gameRepository)
                .environmentObject(gameLaunchUseCase)
                .environmentObject(playerListViewModel)
                .environmentObject(sparkleUpdateService)
                .environmentObject(generalSettingsManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
        }
        
        // Application window group
        appWindowGroups()
            .windowStyle(.titleBar)
            .applyRestorationBehaviorDisabled()
            .windowResizability(.contentSize)
        
        // Status bar in the upper right corner (can display icons)
        MenuBarExtra {
            Button("AI Assistant") {
                AIChatManager.shared.openChatWindow()
            }
        } label: {
            Image("menu-png")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        }
    }
}

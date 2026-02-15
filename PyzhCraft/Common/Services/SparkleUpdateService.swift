import Foundation
import Sparkle

/// Sparkle update service
class SparkleUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdateService()

    private var updater: SPUUpdater?

    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var currentVersion = ""
    @Published var latestVersion = ""
    @Published var updateDescription = ""

    // Configuration options
    private let startupCheckDelay: TimeInterval = 2.0 // Delay check time after startup (seconds)

    override private init() {
        super.init()
        currentVersion = Bundle.main.appVersion
        setupUpdater()
        // Silently check for updates after a 2 second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + startupCheckDelay) { [weak self] in
            self?.checkForUpdatesSilently()
        }
    }

    /// Set up the Sparkle updater
    private func setupUpdater() {
        let hostBundle = Bundle.main
        let driver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)

        do {
            updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: driver, delegate: self)

            setSparkleLanguage()

            try updater?.start()

            // Add these configurations to ensure the "Prompt me later" feature works properly
            updater?.automaticallyChecksForUpdates = true
            updater?.updateCheckInterval = 24 * 60 * 60 // Check once every 24 hours
            updater?.sendsSystemProfile = false
        } catch {
            Logger.shared.error("初始化更新器失败：\(error.localizedDescription)")
        }
    }

    /// Set Sparkle’s language
    private func setSparkleLanguage() {
        let selectedLanguage = LanguageManager.shared.selectedLanguage
        UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
    }

    /// Public method: Set Sparkle’s language
    /// - Parameter language: language code
    func updateSparkleLanguage(_ language: String) {
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }

    // MARK: - SPUUpdaterDelegate

    /// Provide feed URL - select the corresponding appcast file based on system architecture
    func feedURLString(for updater: SPUUpdater) -> String? {
        let architecture = getSystemArchitecture()
        let appcastURL = URLConfig.API.GitHub.appcastURL(architecture: architecture)
        return appcastURL.absoluteString
    }

    /// Update check completed (no updates)
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Logger.shared.info("检查完成，未发现新版本")
        isCheckingForUpdates = false
        updateAvailable = false
    }

    /// Update check completed (there are updates)
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.shared.info("发现新版本：\(item.versionString)")
        isCheckingForUpdates = false
        updateAvailable = true
        latestVersion = item.versionString
        updateDescription = item.itemDescription ?? ""
    }

    /// Update check failed
    func updater(_ updater: SPUUpdater, didFailToCheckForUpdatesWithError error: Error) {
        Logger.shared.error("更新检查失败：\(error.localizedDescription)")
        isCheckingForUpdates = false
        updateAvailable = false
    }

    /// Update session starts
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Logger.shared.info("开始安装更新：\(item.versionString)")
        isCheckingForUpdates = false
    }

    /// Update session ends
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Logger.shared.info("更新清单加载完成")
    }

    /// Get system architecture
    private func getSystemArchitecture() -> String {
        Architecture.current.sparkleArch
    }

    // MARK: - Public Methods

    /// Get the current system architecture
    func getCurrentArchitecture() -> String {
        getSystemArchitecture()
    }

    /// Check updater status
    func getUpdaterStatus() -> (isInitialized: Bool, sessionInProgress: Bool, isChecking: Bool) {
        guard let updater = updater else {
            return (isInitialized: false, sessionInProgress: false, isChecking: isCheckingForUpdates)
        }
        return (isInitialized: true, sessionInProgress: updater.sessionInProgress, isChecking: isCheckingForUpdates)
    }

    /// Manually check for updates (shows Sparkle standard UI)
    func checkForUpdatesWithUI() {
        guard let updater = updater else {
            Logger.shared.error("更新器尚未初始化")
            return
        }

        // Check if an update session is in progress
        if updater.sessionInProgress {
            Logger.shared.warning("更新会话正在进行中，跳过重复的更新检查")
            return
        }

        // Set check status
        isCheckingForUpdates = true

        updater.checkForUpdates()
    }

    /// Check for updates silently (no UI)
    func checkForUpdatesSilently() {
        guard let updater = updater else {
            Logger.shared.error("更新器尚未初始化")
            return
        }

        // Check if an update session is in progress
        if updater.sessionInProgress {
            Logger.shared.warning("更新会话正在进行中，跳过重复的更新检查")
            return
        }

        // Set check status
        isCheckingForUpdates = true

        updater.checkForUpdatesInBackground()
    }
}

// Intercept download requests and add proxy prefixes to GitHub resource addresses as needed
extension SparkleUpdateService {
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        guard let originalURL = request.url else { return }

        let proxiedURL = URLConfig.applyGitProxyIfNeeded(originalURL)
        if proxiedURL != originalURL {
            Logger.shared.info("更新下载链接已重写：\(originalURL.absoluteString) -> \(proxiedURL.absoluteString)")
            request.url = proxiedURL
        }
    }
}

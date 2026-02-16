import SwiftUI
import Combine

// MARK: - Base Game Form View Model
@MainActor
class BaseGameFormViewModel: ObservableObject, GameFormStateProtocol {
    @Published var isDownloading = false
    @Published var isFormValid = false
    @Published var triggerConfirm = false
    @Published var triggerCancel = false

    let gameSetupService = GameSetupUtil()
    let gameNameValidator: GameNameValidator

    internal var downloadTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()
    let configuration: GameFormConfiguration

    init(configuration: GameFormConfiguration) {
        self.configuration = configuration
        self.gameNameValidator = GameNameValidator(gameSetupService: gameSetupService)

        // Monitor state changes of child objects
        setupObservers()

        // Set initial state
        updateParentState()
    }

    private func setupObservers() {
        // Listen for changes in gameNameValidator
        gameNameValidator.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateParentState()
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        // Monitor changes in gameSetupService
        gameSetupService.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateParentState()
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - GameFormStateProtocol Implementation
    func handleCancel() {
        if isDownloading {
            // Stop download task
            downloadTask?.cancel()
            downloadTask = nil

            // Cancel download status
            gameSetupService.downloadState.cancel()

            // Perform post-cancellation cleanup
            Task {
                await performCancelCleanup()
            }
        } else {
            configuration.actions.onCancel()
        }
    }

    func handleConfirm() {
        downloadTask?.cancel()
        downloadTask = Task {
            await performConfirmAction()
        }
    }

    func updateParentState() {
        let newIsDownloading = computeIsDownloading()
        let newIsFormValid = computeIsFormValid()

        // Use DispatchQueue.main.async to avoid modifying state during view updates
        DispatchQueue.main.async { [weak self] in
            self?.configuration.isDownloading.wrappedValue = newIsDownloading
            self?.configuration.isFormValid.wrappedValue = newIsFormValid

            // Synchronize local state
            self?.isDownloading = newIsDownloading
            self?.isFormValid = newIsFormValid
        }
    }

    // MARK: - Virtual Methods (to be overridden)

    func performConfirmAction() async {
        // Override in subclasses
        configuration.actions.onConfirm()
    }

    func performCancelCleanup() async {
        // Override in subclasses for custom cleanup logic
        // Default implementation: reset download status and close window
        await MainActor.run {
            gameSetupService.downloadState.reset()
            configuration.actions.onCancel()
        }
    }

    func computeIsDownloading() -> Bool {
        gameSetupService.downloadState.isDownloading
    }

    func computeIsFormValid() -> Bool {
        gameNameValidator.isFormValid
    }

    // MARK: - Common Download Management
    func startDownloadTask(_ task: @escaping () async -> Void) {
        downloadTask?.cancel()
        downloadTask = Task {
            await task()
        }
    }

    func cancelDownloadIfNeeded() {
        if isDownloading {
            downloadTask?.cancel()
            downloadTask = nil
        } else {
            configuration.actions.onCancel()
        }
    }

    // MARK: - Setup Methods
    func handleNonCriticalError(_ error: GlobalError, message: String) {
        Logger.shared.error("\(message): \(error.chineseMessage)")
        GlobalErrorHandler.shared.handle(error)
    }
}

import SwiftUI
import UniformTypeIdentifiers

// MARK: - LauncherImportView
struct LauncherImportView: View {
    @StateObject private var viewModel: LauncherImportViewModel
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var playerListViewModel: PlayerListViewModel

    // Bindings from parent
    private let triggerConfirm: Binding<Bool>
    private let triggerCancel: Binding<Bool>
    @Environment(\.dismiss)
    private var dismiss

    // File picker status
    @State private var showFolderPicker = false

    // MARK: - Initializer
    init(configuration: GameFormConfiguration) {
        self.triggerConfirm = configuration.triggerConfirm
        self.triggerCancel = configuration.triggerCancel

        self._viewModel = StateObject(wrappedValue: LauncherImportViewModel(
            configuration: configuration
        ))
    }

    // MARK: - Body
    var body: some View {
        formContentView
            .onAppear {
                viewModel.setup(gameRepository: gameRepository, playerListViewModel: playerListViewModel)
            }
            .onDisappear {
                // Clear cache when Sheet is closed
                viewModel.cleanup()
            }
            .gameFormStateListeners(viewModel: viewModel, triggerConfirm: triggerConfirm, triggerCancel: triggerCancel)
            .onChange(of: viewModel.selectedLauncherType) { _, _ in
                // Clear previous selection when launcher type changes
                viewModel.selectedInstancePath = nil
            }
            .onChange(of: viewModel.selectedInstancePath) { _, newValue in
                // When the selected instance path changes, automatically fill in the game name into the input box
                if newValue != nil {
                    viewModel.autoFillGameNameIfNeeded()
                    // Check if Mod Loader supports it and display notification if not
                    viewModel.checkAndNotifyUnsupportedModLoader()
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            .fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: - View Components

    private var formContentView: some View {
        VStack(spacing: 16) {
            launcherSelectionSection
            pathSelectionSection
            if viewModel.currentInstanceInfo != nil {
                instanceInfoSection
            }
            gameNameInputSection
            if viewModel.shouldShowProgress {
                VStack(spacing: 16) {
                    // Show copy progress (if copying is in progress)
                    if viewModel.isImporting, let progress = viewModel.importProgress {
                        importProgressSection(progress: progress)
                    }
                    // Show download progress
                    downloadProgressSection
                }
                .padding(.top, 10)
            }
        }
    }

    private var launcherSelectionSection: some View {
        FormSection {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Launcher")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $viewModel.selectedLauncherType) {
                    ForEach(ImportLauncherType.allCases, id: \.self) { launcherType in
                        Text(launcherType.rawValue)
                            .tag(launcherType)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var pathSelectionSection: some View {
        FormSection {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Instance Folder")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    if let path = viewModel.selectedInstancePath?.path {
                        PathBreadcrumbView(path: path)
                    } else {
                        Text("No path selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Browse") {
                        selectLauncherPath()
                    }
                }
            }
        }
    }

    @ViewBuilder private var instanceInfoSection: some View {
        if let info = viewModel.currentInstanceInfo {
            FormSection {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Game name
                        HStack {
                            Text("Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(info.gameName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // game version
                        HStack {
                            Text("Version")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Label(info.gameVersion, systemImage: "gamecontroller.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Mod loader
                        if !info.modLoader.isEmpty && info.modLoader != "vanilla" {
                            HStack {
                                Text("Mod Loader")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Label(info.modLoader.capitalized, systemImage: "puzzlepiece.extension.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if !info.modLoaderVersion.isEmpty {
                                        Text("(\(info.modLoaderVersion))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var gameNameInputSection: some View {
        FormSection {
            GameNameInputView(
                gameName: Binding(
                    get: { viewModel.gameNameValidator.gameName },
                    set: { viewModel.gameNameValidator.gameName = $0 }
                ),
                isGameNameDuplicate: Binding(
                    get: { viewModel.gameNameValidator.isGameNameDuplicate },
                    set: { viewModel.gameNameValidator.isGameNameDuplicate = $0 }
                ),
                isDisabled: viewModel.isImporting || viewModel.isDownloading,
                gameSetupService: viewModel.gameSetupService
            )
        }
    }

    private var downloadProgressSection: some View {
        // Get the modLoader of the selected instance, or use "vanilla" if there is none
        let selectedModLoader: String = {
            if let info = viewModel.currentInstanceInfo {
                return info.modLoader
            }
            return "vanilla"
        }()

        return DownloadProgressSection(
            gameSetupService: viewModel.gameSetupService,
            selectedModLoader: selectedModLoader,
            modPackViewModel: nil,
            modPackIndexInfo: nil
        )
    }

    private func importProgressSection(progress: (fileName: String, completed: Int, total: Int)) -> some View {
        FormSection {
            DownloadProgressRow(
                title: "Copy Files",
                progress: progress.total > 0 ? Double(progress.completed) / Double(progress.total) : 0.0,
                currentFile: progress.fileName,
                completed: progress.completed,
                total: progress.total,
                version: nil
            )
        }
    }

    // MARK: - Helper Methods

    private func selectLauncherPath() {
        showFolderPicker = true
    }

    /// Handles folders selected via fileImporter
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Maintain security-scoped resource access
            guard url.startAccessingSecurityScopedResource() else {
                GlobalErrorHandler.shared.handle(
                    GlobalError.fileSystem(i18nKey: "File Access Failed",
                        level: .notification
                    )
                )
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            // Verify that the selected folder is a valid instance
            guard viewModel.validateInstance(at: url) else {
                let launcherName = viewModel.selectedLauncherType.rawValue
                GlobalErrorHandler.shared.handle(
                    GlobalError.fileSystem(i18nKey: "Invalid Instance Path",
                        level: .notification
                    )
                )
                return
            }

            // Directly use the selected instance path
            viewModel.selectedInstancePath = url

            // Automatically fill in the game name into the input box
            viewModel.autoFillGameNameIfNeeded()

            Logger.shared.info("成功选择 \(viewModel.selectedLauncherType.rawValue) 实例路径: \(url.path)")

        case .failure(let error):
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    #Preview {
        struct PreviewWrapper: View {
            @State private var isDownloading = false
            @State private var isFormValid = false
            @State private var triggerConfirm = false
            @State private var triggerCancel = false

            var body: some View {
                LauncherImportView(
                    configuration: GameFormConfiguration(
                        isDownloading: $isDownloading,
                        isFormValid: $isFormValid,
                        triggerConfirm: $triggerConfirm,
                        triggerCancel: $triggerCancel,
                        onCancel: {},
                        onConfirm: {}
                    )
                )
                .environmentObject(GameRepository())
                .environmentObject(PlayerListViewModel())
                .frame(width: 600, height: 500)
                .padding()
            }
        }
        return PreviewWrapper()
    }
}

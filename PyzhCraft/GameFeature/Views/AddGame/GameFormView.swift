import SwiftUI
import UniformTypeIdentifiers

// MARK: - Game Form Mode
enum GameFormMode {
    case creation
    case modPackImport(file: URL, shouldProcess: Bool)
    case launcherImport

    var isImportMode: Bool {
        switch self {
        case .creation:
            return false
        case .modPackImport, .launcherImport:
            return true
        }
    }
}

// MARK: - GameFormView
struct GameFormView: View {
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @Environment(\.dismiss)
    private var dismiss

    // MARK: - File Picker Type
    enum FilePickerType {
        case modPack, gameIcon
    }

    // MARK: - State
    @State private var isDownloading = false
    @State private var isFormValid = false
    @State private var triggerConfirm = false
    @State private var triggerCancel = false
    @State private var showFilePicker = false
    @State private var filePickerType: FilePickerType = .modPack
    @State private var mode: GameFormMode = .creation
    @State private var isModPackParsed = false
    @State private var imagePickerHandler: ((Result<[URL], Error>) -> Void)?
    @State private var showImportPicker = false

    // MARK: - Body
    @ViewBuilder var body: some View {
        let content = CommonSheetView(
            header: { headerView },
            body: {

                VStack {
                    switch mode {
                    case .creation:
                        GameCreationView(
                            isDownloading: $isDownloading,
                            isFormValid: $isFormValid,
                            triggerConfirm: $triggerConfirm,
                            triggerCancel: $triggerCancel,
                            onCancel: { dismiss() },
                            onConfirm: { dismiss() },
                            onRequestImagePicker: {
                                filePickerType = .gameIcon
                                showFilePicker = true
                            },
                            onSetImagePickerHandler: { handler in
                                imagePickerHandler = handler
                            }
                        )
                    case let .modPackImport(file, shouldProcess):
                        ModPackImportView(
                            configuration: GameFormConfiguration(
                                isDownloading: $isDownloading,
                                isFormValid: $isFormValid,
                                triggerConfirm: $triggerConfirm,
                                triggerCancel: $triggerCancel,
                                onCancel: { dismiss() },
                                onConfirm: { dismiss() }
                            ),
                            preselectedFile: file,
                            shouldStartProcessing: shouldProcess
                        ) { isProcessing in
                            if !isProcessing {
                                if case .modPackImport(let file, _) = mode {
                                    mode = .modPackImport(file: file, shouldProcess: false)
                                }
                                isModPackParsed = true
                            }
                        }
                    case .launcherImport:
                        LauncherImportView(
                            configuration: GameFormConfiguration(
                                isDownloading: $isDownloading,
                                isFormValid: $isFormValid,
                                triggerConfirm: $triggerConfirm,
                                triggerCancel: $triggerCancel,
                                onCancel: { dismiss() },
                                onConfirm: { dismiss() }
                            )
                        )
                    }
                }
            },
            footer: { footerView }
        )

        // When in "Import Launcher" mode, avoid hanging another fileImporter in the parent view
        // Make the subview's fileImporter work properly
        if case .launcherImport = mode {
            content
        } else {
            content
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: {
                        switch filePickerType {
                        case .modPack:
                            return [
                                UTType(filenameExtension: "mrpack") ?? UTType.data,
                                .zip,
                                UTType(filenameExtension: "zip") ?? UTType.zip,
                            ]
                        case .gameIcon:
                            return [.png, .jpeg, .gif]
                        }
                    }(),
                    allowsMultipleSelection: false
                ) { result in
                    switch filePickerType {
                    case .modPack:
                        handleModPackFileSelection(result)
                    case .gameIcon:
                        imagePickerHandler?(result)
                    }
                }
        }
    }

    // MARK: - View Components
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text(currentModeTitle)
                    .font(.headline)
                Spacer()
                importModePicker
            }
        }
    }

    private var currentModeTitle: LocalizedStringKey {
        switch mode {
        case .creation:
            return LocalizedStringKey("New")
        case .modPackImport:
            return LocalizedStringKey("Import Modpack")
        case .launcherImport:
            return LocalizedStringKey("Import Launcher")
        }
    }

    private var importModePicker: some View {
        Menu {
            Button {
                mode = .creation
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }

            Button {
                // First switch to non-launcherImport mode
                if case .launcherImport = mode {
                    mode = .creation
                }
                filePickerType = .modPack
                // Asynchronously wait for view updates
                DispatchQueue.main.async {
                    showFilePicker = true
                }
            } label: {
                Label("Import Modpack", systemImage: "square.and.arrow.up")
            }

            Button {
                mode = .launcherImport
            } label: {
                Label("Import Launcher", systemImage: "arrow.down.doc")
            }
        } label: {
            Text(currentModeTitle)
        }
        .fixedSize()
        .help("Import Modpack")
    }

    private var footerView: some View {
        HStack {
            cancelButton
            Spacer()
            confirmButton
        }
    }

    private var cancelButton: some View {
        Button {
            if isDownloading {
                // When downloading, trigger cancellation processing logic
                triggerCancel = true
            } else {
                // Directly close the window when not downloading
                dismiss()
            }
        } label: {
            Text(
                isDownloading
                    ? LocalizedStringKey("Stop")
                    : LocalizedStringKey("Cancel")
            )
        }
        .keyboardShortcut(.cancelAction)
    }

    private var confirmButton: some View {
        Button {
            triggerConfirm = true
        } label: {
            HStack {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    let buttonText: LocalizedStringKey = {
                        switch mode {
                        case .modPackImport:
                            return LocalizedStringKey("Import")
                        case .launcherImport:
                            return LocalizedStringKey("Import")
                        case .creation:
                            return LocalizedStringKey("Confirm")
                        }
                    }()
                    Text(buttonText)
                }
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!isFormValid || isDownloading)
    }

    // MARK: - Helper Methods

    private func handleModPackFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                let globalError = GlobalError.fileSystem(i18nKey: "File Access Failed",
                    level: .notification
                )
                GlobalErrorHandler.shared.handle(globalError)
                return
            }

            let urlForBackground = url
            Task {
                let tempFileResult: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        let tempDir = FileManager.default.temporaryDirectory
                            .appendingPathComponent("modpack_import")
                            .appendingPathComponent(UUID().uuidString)
                        try FileManager.default.createDirectory(
                            at: tempDir,
                            withIntermediateDirectories: true
                        )
                        let tempFile = tempDir.appendingPathComponent(urlForBackground.lastPathComponent)
                        try FileManager.default.copyItem(at: urlForBackground, to: tempFile)
                        return .success(tempFile)
                    } catch {
                        return .failure(error)
                    }
                }.value
                urlForBackground.stopAccessingSecurityScopedResource()

                await MainActor.run {
                    switch tempFileResult {
                    case .success(let tempFile):
                        mode = .modPackImport(file: tempFile, shouldProcess: true)
                        isModPackParsed = false
                    case .failure(let error):
                        GlobalErrorHandler.shared.handle(GlobalError.from(error))
                    }
                }
            }

        case .failure(let error):
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }
    }
}

#Preview {
    GameFormView()
}

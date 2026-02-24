import SwiftUI
import UniformTypeIdentifiers

/// Integration package document type, used for file export
struct ModPackDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "mrpack") ?? UTType.zip]
    }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Integration package export Sheet view
/// Provides integration package export functions, including:
/// - Export form (name, version, description)
/// - Export progress display
/// - Export completion prompt
/// - File save dialog
struct ModPackExportSheet: View {
    // MARK: - Properties
    let gameInfo: GameVersionInfo
    @Environment(\.dismiss)
    private var dismiss
    @StateObject private var viewModel: ModPackExportViewModel
    @State private var showSaveErrorAlert = false
    @State private var isExporting = false
    @State private var exportDocument: ModPackDocument?
    
    // MARK: - Initialization
    init(gameInfo: GameVersionInfo) {
        self.gameInfo = gameInfo
        let viewModel = ModPackExportViewModel()
        // Set default value on initialization
        if viewModel.modPackName.isEmpty {
            viewModel.modPackName = gameInfo.gameName
        }
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyView },
            footer: { footerView }
        )
        .onDisappear {
            viewModel.cleanupAllData()
        }
        .onChange(of: viewModel.shouldShowSaveDialog) { _, shouldShow in
            if shouldShow, let tempPath = viewModel.tempExportPath {
                handleExportCompleted(tempFilePath: tempPath)
            }
        }
        .onChange(of: isExporting) { oldValue, newValue in
            if oldValue && !newValue && exportDocument != nil {
                exportDocument = nil
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: UTType(filenameExtension: "mrpack") ?? UTType.zip,
            defaultFilename: viewModel.modPackName.isEmpty ? "modpack" : viewModel.modPackName
        ) { result in
            switch result {
            case .success(let url):
                Logger.shared.info("The integration package has been saved to: \(url.path)")
                viewModel.handleSaveSuccess()
                dismiss()
            case .failure(let error):
                Logger.shared.error("Failed to save file: \(error.localizedDescription)")
                viewModel.handleSaveFailure(error: error.localizedDescription)
            }
            exportDocument = nil
        }
        .alert("Error", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) {
                viewModel.saveError = nil
            }
        } message: {
            if let error = viewModel.saveError {
                Text(error)
            }
        }
        .onChange(of: viewModel.saveError) { _, error in
            showSaveErrorAlert = error != nil
        }
    }
    
    private var headerView: some View {
        Text("Export Modpack")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder private var bodyView: some View {
        switch viewModel.exportState {
        case .idle:
            idleStateView
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .exporting, .completed:
            exportProgressView
        }
    }
    
    // MARK: - State Views
    
    @ViewBuilder private var idleStateView: some View {
        if let error = viewModel.exportError {
            errorView(error: error)
        } else {
            exportFormView
        }
    }
    
    private var exportFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Integrated package name
            VStack(alignment: .leading, spacing: 8) {
                Text("Modpack Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Enter modpack name", text: $viewModel.modPackName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Integrated package version
            VStack(alignment: .leading, spacing: 8) {
                Text("Modpack Version")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("1.0.0", text: $viewModel.modPackVersion)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var exportProgressView: some View {
        VStack(alignment: .leading, spacing: 16) {
            exportFormView
            progressItemsView
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                if viewModel.isExporting {
                    viewModel.cancelExport()
                }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Export") {
                if viewModel.exportState == .completed, let tempPath = viewModel.tempExportPath {
                    handleExportCompleted(tempFilePath: tempPath)
                } else {
                    viewModel.startExport(gameInfo: gameInfo)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.modPackName.isEmpty || viewModel.isExporting)
        }
    }
    
    // MARK: - Reusable Components
    
    private var progressItemsView: some View {
        VStack(spacing: 16) {
            // Scan resource progress bar (always shown because scanning is inevitable)
            if let scanProgress = viewModel.exportProgress.scanProgress {
                progressRow(progress: scanProgress)
                    .id("scan-\(scanProgress.completed)-\(scanProgress.total)")
            }
            
            // Copy file progress bar (only displayed when there is a copy task, no placeholder is displayed)
            if let copyProgress = viewModel.exportProgress.copyProgress {
                progressRow(progress: copyProgress)
                    .id("copy-\(copyProgress.completed)-\(copyProgress.total)")
            }
        }
    }
    
    private func progressRow(progress: ModPackExporter.ExportProgress.ProgressItem) -> some View {
        FormSection {
            DownloadProgressRow(
                title: progress.title,
                progress: progress.progress,
                currentFile: progress.currentFile,
                completed: progress.completed,
                total: progress.total,
                version: nil
            )
        }
        .frame(minHeight: 70)
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 48))
            
            Text("Export Failed")
                .font(.headline)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Actions
    
    /// The export process is completed and the save dialog box is displayed
    private func handleExportCompleted(tempFilePath: URL) {
        if viewModel.shouldShowSaveDialog {
            viewModel.markSaveDialogShown()
        }
        
        Task {
            do {
                let fileData = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: tempFilePath)
                }.value
                await MainActor.run {
                    self.exportDocument = ModPackDocument(data: fileData)
                    self.isExporting = true
                }
            } catch {
                Logger.shared.error("Failed to read temporary file: \(error.localizedDescription)")
                viewModel.handleSaveFailure(error: error.localizedDescription)
            }
        }
    }
}

import SwiftUI

/// Integration package export view model
/// Manage the status and business logic of the integration package export process
@MainActor
class ModPackExportViewModel: ObservableObject {
    // MARK: - Export State

    /// Export status enum
    enum ExportState: Equatable {
        case idle              // Idle state, display form
        case exporting         // Exporting, showing progress
        case completed         // Export completed, waiting to save, display progress (100%)
    }

    // MARK: - Published Properties

    /// export status
    @Published var exportState: ExportState = .idle

    /// Export progress information
    @Published var exportProgress = ModPackExporter.ExportProgress()

    /// Integrated package name
    @Published var modPackName: String = ""

    /// Integrated package version
    @Published var modPackVersion: String = "1.0.0"

    /// Integration package description
    @Published var summary: String = ""

    /// Export error message
    @Published var exportError: String?

    /// Temporary file path. When there is a value, it means that the packaging is completed and the save dialog box needs to be displayed
    @Published var tempExportPath: URL?

    /// Error message when saving file
    @Published var saveError: String?

    // MARK: - Private Properties

    /// Export tasks
    private var exportTask: Task<Void, Never>?

    /// Whether the save dialog box has been displayed (to prevent repeated display)
    private var hasShownSaveDialog = false

    // MARK: - Computed Properties

    /// Is exporting
    var isExporting: Bool {
        exportState == .exporting
    }

    /// Whether the save dialog should be shown
    var shouldShowSaveDialog: Bool {
        tempExportPath != nil && !hasShownSaveDialog
    }

    // MARK: - Export Actions

    func startExport(gameInfo: GameVersionInfo) {
        guard exportState == .idle else { return }

        if modPackName.isEmpty {
            modPackName = gameInfo.gameName
        }

        exportState = .exporting
        exportProgress = ModPackExporter.ExportProgress()
        exportError = nil
        tempExportPath = nil
        hasShownSaveDialog = false
        saveError = nil

        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(modPackName).mrpack")

        exportTask = Task {
            let result = await ModPackExporter.exportModPack(
                gameInfo: gameInfo,
                outputPath: tempPath,
                modPackName: modPackName,
                modPackVersion: modPackVersion,
                summary: nil
            ) { progress in
                Task { @MainActor in
                    self.exportProgress = progress
                }
            }

            await MainActor.run {
                if result.success {
                    self.exportState = .completed
                    self.tempExportPath = result.outputPath
                    Logger.shared.info("整合包导出到临时位置成功: \(result.outputPath?.path ?? "未知路径")")
                } else {
                    self.cleanupTempFile()
                    self.exportState = .idle
                    self.exportError = result.message
                    self.exportProgress = ModPackExporter.ExportProgress()
                    Logger.shared.error("整合包导出失败: \(result.message)")
                }
            }
        }
    }

    /// Cancel export task
    func cancelExport() {
        exportTask?.cancel()
        cleanupTempFile()
        exportState = .idle
        exportProgress = ModPackExporter.ExportProgress()
        exportError = nil
        hasShownSaveDialog = false
        saveError = nil
    }

    // MARK: - Save Dialog Actions

    /// Mark save dialog is shown (to prevent repeated display)
    func markSaveDialogShown() {
        hasShownSaveDialog = true
    }

    func handleSaveSuccess() {
        cleanupTempFile()
        hasShownSaveDialog = false
        saveError = nil
        exportState = .idle
        exportProgress = ModPackExporter.ExportProgress()
    }

    func handleSaveFailure(error: String) {
        saveError = error
        cleanupTempFile()
        hasShownSaveDialog = false
    }

    func cleanupAllData() {
        exportTask?.cancel()
        exportTask = nil
        cleanupTempFile()
        cleanupTempDirectories()
        exportState = .idle
        exportProgress = ModPackExporter.ExportProgress()
        exportError = nil
        tempExportPath = nil
        hasShownSaveDialog = false
        saveError = nil
        modPackName = ""
        modPackVersion = "1.0.0"
        summary = ""
    }

    // MARK: - Private Helper Methods

    private func cleanupTempFile() {
        guard let tempPath = tempExportPath else { return }
        do {
            if FileManager.default.fileExists(atPath: tempPath.path) {
                try FileManager.default.removeItem(at: tempPath)
                Logger.shared.info("已清理临时文件: \(tempPath.path)")
            }
        } catch {
            Logger.shared.warning("清理临时文件失败: \(error.localizedDescription)")
        }
        tempExportPath = nil
    }

    private func cleanupTempDirectories() {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modpack_export")
        guard FileManager.default.fileExists(atPath: exportDir.path) else { return }
        do {
            try FileManager.default.removeItem(at: exportDir)
            Logger.shared.info("已清理临时导出目录: \(exportDir.path)")
        } catch {
            Logger.shared.warning("清理临时导出目录失败: \(error.localizedDescription)")
        }
    }
}

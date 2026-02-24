import Foundation

// MARK: - Java Download State
@MainActor
class JavaDownloadState: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var isCancelled = false
    @Published var version = ""
    @Published var errorMessage = ""
    @Published var hasError = false
    
    func reset() {
        isDownloading = false
        progress = 0
        currentFile = ""
        isCancelled = false
        version = ""
        errorMessage = ""
        hasError = false
    }
    
    func startDownload(version: String) {
        self.version = version
        self.isDownloading = true
        self.progress = 0
        self.isCancelled = false
        self.hasError = false
        self.errorMessage = ""
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func updateProgress(fileName: String, progress: Double) {
        currentFile = fileName
        self.progress = progress
    }
    
    func setError(_ message: String) {
        hasError = true
        errorMessage = message
        isDownloading = false
    }
}

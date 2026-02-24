import SwiftUI

// MARK: - Download status definition
enum ResourceDownloadState {
    case idle, downloading, success, failed
}

// MARK: - Dependency management ViewModel
/// Persistent dependency-related state, used to manage the download and installation of resource dependencies
final class DependencySheetViewModel: ObservableObject {
    @Published var missingDependencies: [ModrinthProjectDetail] = []
    @Published var isLoadingDependencies = true
    @Published var showDependenciesSheet = false
    @Published var dependencyDownloadStates: [String: ResourceDownloadState] = [:]
    @Published var dependencyVersions: [String: [ModrinthProjectDetailVersion]] = [:]
    @Published var selectedDependencyVersion: [String: String] = [:]
    @Published var overallDownloadState: OverallDownloadState = .idle
    
    enum OverallDownloadState {
        case idle  // Initial state, or after all downloads are successful
        case failed  // Any files failed during the first "Download All" operation
        case retrying  // User is retrying failed item
    }
    
    var allDependenciesDownloaded: Bool {
        // When there are no dependencies, it is also considered that "all dependencies have been downloaded"
        if missingDependencies.isEmpty { return true }
        
        // Check if all listed dependencies are marked as successful
        return missingDependencies.allSatisfy {
            dependencyDownloadStates[$0.id] == .success
        }
    }
    
    func resetDownloadStates() {
        for dep in missingDependencies {
            dependencyDownloadStates[dep.id] = .idle
        }
        overallDownloadState = .idle
    }
    
    /// Cleans up all data, called when sheet is closed to free memory
    func cleanup() {
        missingDependencies = []
        isLoadingDependencies = true
        dependencyDownloadStates = [:]
        dependencyVersions = [:]
        selectedDependencyVersion = [:]
        overallDownloadState = .idle
    }
}

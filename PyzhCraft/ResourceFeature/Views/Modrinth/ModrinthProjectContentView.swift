import SwiftUI

// MARK: - Constants
enum ModrinthProjectContentConstants {
    static let maxVisibleVersions = 15
    static let popoverWidth: CGFloat = 300
    static let popoverHeight: CGFloat = 400
    static let cornerRadius: CGFloat = 4
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 8
}

struct ModrinthProjectContentView: View {
    @State private var isLoading = false
    @State private var error: GlobalError?
    @Binding var projectDetail: ModrinthProjectDetail?
    let projectId: String
    
    var body: some View {
        VStack {
            if isLoading && projectDetail == nil && error == nil {
                loadingView
            } else if let error {
                newErrorView(error)
            } else if let project = projectDetail {
                CompatibilitySection(project: project)
                LinksSection(project: project)
                DetailsSection(project: project)
            }
        }
        .task(id: projectId) { await loadProjectDetails() }
        .onDisappear {
            projectDetail = nil
            error = nil
        }
    }
    
    private func loadProjectDetails() async {
        isLoading = true
        error = nil
        
        do {
            try await loadProjectDetailsThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to load project details: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            await MainActor.run {
                self.error = globalError
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(ModrinthProjectContentConstants.padding)
    }
    
    private func loadProjectDetailsThrowing() async throws {
        guard !projectId.isEmpty else {
            throw GlobalError.validation(
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }
        
        guard
            let fetchedProject = await ModrinthService.fetchProjectDetails(id: projectId)
        else {
            throw GlobalError.resource(
                i18nKey: "Project Details Not Found",
                level: .notification
            )
        }
        
        await MainActor.run {
            projectDetail = fetchedProject
        }
    }
}

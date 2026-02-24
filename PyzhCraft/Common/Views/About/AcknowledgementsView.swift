import SwiftUI

public struct AcknowledgementsView: View {
    @State private var libraries: [OpenSourceLibrary] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var loadTask: Task<Void, Never>?
    private let gitHubService = GitHubService.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoading {
                    loadingView
                } else {
                    librariesContent
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            // Reload data every time you open it
            loadLibraries()
        }
        .onDisappear {
            clearAllData()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
    
    // MARK: - Libraries Content
    private var librariesContent: some View {
        LazyVStack(spacing: 0) {
            if !libraries.isEmpty {
                librariesList
            } else if loadFailed {
                errorView
            }
        }
    }
    
    // MARK: - Libraries List
    private var librariesList: some View {
        VStack(spacing: 0) {
            ForEach(libraries.indices, id: \.self) { index in
                libraryRow(libraries[index])
                    .id("library-\(index)")
                
                if index < libraries.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    // MARK: - Library Row
    private func libraryRow(_ library: OpenSourceLibrary) -> some View {
        Group {
            if let url = URL(string: library.url) {
                Link(destination: url) {
                    libraryRowContent(library)
                }
            } else {
                libraryRowContent(library)
            }
        }
    }
    
    // MARK: - Library Row Content
    private func libraryRowContent(_ library: OpenSourceLibrary) -> some View {
        HStack(spacing: 12) {
            // avatar
            libraryAvatar(library)
            
            // Information section
            VStack(alignment: .leading, spacing: 4) {
                // library name
                Text(library.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                // Description (with popover)
                if let description = library.description, !description.isEmpty {
                    DescriptionTextWithPopover(description: description)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // arrow icon
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    // MARK: - Library Avatar
    private func libraryAvatar(_ library: OpenSourceLibrary) -> some View {
        Group {
            if let avatarURL = library.avatar {
                // Optimized avatar URL (using thumbnail parameter)
                let optimizedURL = optimizedAvatarURL(from: avatarURL, size: 40)
                AsyncImage(url: optimizedURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.3))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            )
                    @unknown default:
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            )
                    }
                }
                .frame(width: 40, height: 40)
                .cornerRadius(8)
                .clipped()
            } else {
                Rectangle()
                    .foregroundColor(.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.caption)
                    )
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            }
        }
    }
    
    /// Get optimized avatar URL (use thumbnail parameter to reduce download size)
    /// - Parameters:
    ///   - avatarURL: original avatar URL
    ///   - size: display size (pixels)
    /// - Returns: optimized URL
    private func optimizedAvatarURL(from avatarURL: String, size: CGFloat) -> URL? {
        guard let url = URL(string: avatarURL) else { return nil }
        
        // If it is already a GitHub avatar URL, add the size parameter
        // GitHub avatar URL format: https://avatars.githubusercontent.com/u/xxx or https://github.com/identicons/xxx.png
        if url.host?.contains("github.com") == true || url.host?.contains("avatars.githubusercontent.com") == true {
            // Calculate required pixel size (@2x screen requires 2x)
            let pixelSize = Int(size * 2)
            // Remove existing query parameters (if any)
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "s", value: "\(pixelSize)")]
            return components?.url
        }
        
        return url
    }
    
    // MARK: - Error View
    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.title2)
            Text("Network Request Failed")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
    }
    
    // MARK: - Load Libraries
    private func loadLibraries() {
        // Cancel the previous task (if it exists)
        loadTask?.cancel()
        
        // reset state
        isLoading = true
        loadFailed = false
        
        loadTask = Task {
            do {
                // Check cancellation status before async operation starts
                try Task.checkCancellation()
                
                let decodedLibraries: [OpenSourceLibrary] = try await gitHubService.fetchAcknowledgements()
                
                // Check cancellation status again before updating UI
                try Task.checkCancellation()
                
                await MainActor.run {
                    // One last check for cancellation status (because it may have been canceled during await)
                    guard !Task.isCancelled else { return }
                    
                    libraries = decodedLibraries
                    isLoading = false
                    loadFailed = false
                    Logger.shared.info(
                        "Successfully loaded",
                        libraries.count,
                        "libraries from GitHubService"
                    )
                }
            } catch is CancellationError {
                // The task is canceled and processed silently (no log is required, this is normal cleanup behavior)
            } catch {
                // Check if the task has been canceled (avoid updating status after cancellation)
                guard !Task.isCancelled else { return }
                
                Logger.shared.error("Failed to load libraries from GitHubService:", error)
                await MainActor.run {
                    // Last check for cancellation status
                    guard !Task.isCancelled else { return }
                    
                    loadFailed = true
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Clear Libraries Data
    private func clearLibrariesData() {
        // Cancel a running load task
        loadTask?.cancel()
        loadTask = nil
        
        libraries = []
        isLoading = true
        loadFailed = false
        Logger.shared.info("Libraries data cleared")
    }
    
    /// Clean all data
    private func clearAllData() {
        clearLibrariesData()
    }
    
    // MARK: - JSON Data Models
    private struct OpenSourceLibrary: Codable {
        let name: String
        let url: String
        let avatar: String?
        let description: String?
        
        enum CodingKeys: String, CodingKey {
            case name, url, avatar, description
        }
    }
}

// MARK: - Description Text With Popover
private struct DescriptionTextWithPopover: View {
    let description: String
    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?
    
    var body: some View {
        Button {
            // Also show popover when clicked
            showPopover.toggle()
        } label: {
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            // Cancel previous task
            hoverTask?.cancel()
            
            if hovering {
                // Delay the display of popover to avoid frequent display when the mouse moves quickly
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    if !Task.isCancelled && isHovering {
                        await MainActor.run {
                            showPopover = true
                        }
                    }
                }
            } else {
                showPopover = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(minWidth: 200, maxWidth: 500)
            .fixedSize(horizontal: true, vertical: false)
        }
        .onDisappear {
            hoverTask?.cancel()
            showPopover = false
        }
    }
}

#Preview {
    AcknowledgementsView()
}

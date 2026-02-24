import SwiftUI

struct ModrinthDetailCardView: View {
    // MARK: - Properties
    var project: ModrinthProject
    let selectedVersions: [String]
    let selectedLoaders: [String]
    let gameInfo: GameVersionInfo?
    let query: String
    let type: Bool  // false = local, true = server
    @Binding var selectedItem: SidebarItem
    var onResourceChanged: (() -> Void)?
    /// Local resource enable/disable state change callback (only used by local list)
    var onLocalDisableStateChanged: ((ModrinthProject, Bool) -> Void)?
    /// Update success callback: Only the hash and list items of the current entry are updated, and no global scan is performed. Parameters (projectId, oldFileName, newFileName, newHash)
    var onResourceUpdated: ((String, String, String, String?) -> Void)?
    @Binding var scannedDetailIds: Set<String> // detailId Set of scanned resources for quick lookup
    @State private var addButtonState: AddButtonState = .idle
    @State private var showDeleteAlert = false
    @State private var isResourceDisabled = false  // Whether the resource is disabled (for graying effect)
    @EnvironmentObject private var gameRepository: GameRepository
    
    // MARK: - Enums
    enum AddButtonState {
        case idle, loading, installed,
             update  // A new version is available
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: ModrinthConstants.UIConstants.contentSpacing) {
            iconView
            VStack(alignment: .leading, spacing: ModrinthConstants.UIConstants.spacing) {
                titleView
                descriptionView
                tagsView
            }
            Spacer(minLength: 8)
            infoView
        }
        .frame(maxWidth: .infinity)
        .opacity(isResourceDisabled ? 0.5 : 1.0)  // Grayed out when disabled
        .onAppear {
            // Synchronize disabled status from data source to avoid displaying errors when list scrolling reuses rows
            isResourceDisabled = ResourceEnableDisableManager.isDisabled(fileName: project.fileName)
        }
        .onChange(of: project.fileName) { _, newFileName in
            isResourceDisabled = ResourceEnableDisableManager.isDisabled(fileName: newFileName)
        }
    }
    
    // MARK: - View Components
    private var iconView: some View {
        Group {
            // Use id prefix to determine local resources, which is more reliable
            if project.projectId.hasPrefix("local_") || project.projectId.hasPrefix("file_") {
                // Local resources display questionmark.circle icon
                localResourceIcon
            } else if let iconUrl = project.iconUrl,
                      let url = URL(string: iconUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderIcon
                }
                .frame(
                    width: ModrinthConstants.UIConstants.iconSize,
                    height: ModrinthConstants.UIConstants.iconSize
                )
                .cornerRadius(ModrinthConstants.UIConstants.cornerRadius)
                .clipped()
            } else {
                placeholderIcon
            }
        }
    }
    
    private var placeholderIcon: some View {
        Color.gray.opacity(0.2)
            .frame(
                width: ModrinthConstants.UIConstants.iconSize,
                height: ModrinthConstants.UIConstants.iconSize
            )
            .cornerRadius(ModrinthConstants.UIConstants.cornerRadius)
    }
    
    private var localResourceIcon: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: ModrinthConstants.UIConstants.iconSize * 0.6))
            .foregroundColor(.secondary)
            .frame(
                width: ModrinthConstants.UIConstants.iconSize,
                height: ModrinthConstants.UIConstants.iconSize
            )
            .background(Color.gray.opacity(0.2))
            .cornerRadius(ModrinthConstants.UIConstants.cornerRadius)
    }
    
    private var titleView: some View {
        HStack(spacing: 4) {
            Text(project.title)
                .font(.headline)
                .lineLimit(1)
            if type == true {
                Text("by \(project.author)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if type == false, let fileName = project.fileName {
                Text(fileName)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    private var descriptionView: some View {
        Text(project.description)
            .font(.subheadline)
            .lineLimit(ModrinthConstants.UIConstants.descriptionLineLimit)
            .foregroundColor(.secondary)
    }
    
    private var tagsView: some View {
        HStack(spacing: ModrinthConstants.UIConstants.spacing) {
            ForEach(
                Array(
                    project.displayCategories.prefix(
                        ModrinthConstants.UIConstants.maxTags
                    )
                ),
                id: \.self
            ) {
                TagView(text: $0)
            }
            if project.displayCategories.count > ModrinthConstants.UIConstants.maxTags {
                Text(
                    "+\(project.displayCategories.count - ModrinthConstants.UIConstants.maxTags)"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var infoView: some View {
        VStack(alignment: .trailing, spacing: ModrinthConstants.UIConstants.spacing) {
            downloadInfoView
            followerInfoView
            AddOrDeleteResourceButton(
                project: project,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders,
                gameInfo: gameInfo,
                query: query,
                type: type,
                selectedItem: $selectedItem,
                onResourceChanged: onResourceChanged,
                scannedDetailIds: $scannedDetailIds,
                isResourceDisabled: $isResourceDisabled,
                onResourceUpdated: onResourceUpdated
            ) { isDisabled in
                onLocalDisableStateChanged?(project, isDisabled)
            }
            .environmentObject(gameRepository)
        }
    }
    
    private var downloadInfoView: some View {
        InfoRowView(
            icon: "arrow.down.circle",
            text: Self.formatNumber(project.downloads)
        )
    }
    
    private var followerInfoView: some View {
        InfoRowView(
            icon: "heart",
            text: Self.formatNumber(project.follows)
        )
    }
    
    // MARK: - Helper Methods
    static func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            String(format: "%.1fk", Double(num) / 1_000)
        } else {
            "\(num)"
        }
    }
}

// MARK: - Supporting Views
private struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, ModrinthConstants.UIConstants.tagHorizontalPadding)
            .padding(.vertical, ModrinthConstants.UIConstants.tagVerticalPadding)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(ModrinthConstants.UIConstants.tagCornerRadius)
    }
}

private struct InfoRowView: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
}

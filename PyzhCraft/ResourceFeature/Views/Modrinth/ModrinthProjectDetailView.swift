import SwiftMarkDownUI
import SwiftUI

// MARK: - Constants
enum ModrinthProjectDetailConstants {
    static let iconSize: CGFloat = 75
    static let cornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let galleryImageHeight: CGFloat = 160
    static let galleryImageMinWidth: CGFloat = 160
    static let galleryImageMaxWidth: CGFloat = 200
    static let categorySpacing: CGFloat = 6
    static let categoryPadding: CGFloat = 4
    static let categoryVerticalPadding: CGFloat = 2
    static let categoryCornerRadius: CGFloat = 12
}

// MARK: - ModrinthProjectDetailView
struct ModrinthProjectDetailView: View {
    let projectDetail: ModrinthProjectDetail?

    var body: some View {
        if let project = projectDetail {
            projectDetailView(project)
        } else {
            loadingView
        }
    }

    // MARK: - Project Detail View
    private func projectDetailView(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader(project)
            projectContent(project)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // MARK: - Project Header
    private func projectHeader(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: ModrinthProjectDetailConstants.spacing) {
            HStack(alignment: .top, spacing: ModrinthProjectDetailConstants.spacing) {
                projectIcon(project)
                projectInfo(project)
            }
        }
        .padding(.horizontal, ModrinthProjectDetailConstants.padding)
        .padding(.vertical, ModrinthProjectDetailConstants.spacing)
    }

    private func projectIcon(_ project: ModrinthProjectDetail) -> some View {
        Group {
            if let iconUrl = project.iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: ModrinthProjectDetailConstants.iconSize, height: ModrinthProjectDetailConstants.iconSize)
                .cornerRadius(ModrinthProjectDetailConstants.cornerRadius)
                .clipped()
            }
        }
    }

    private func projectInfo(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title)
                .font(.title2.bold())

            Text(project.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)

            projectStats(project)
        }
    }

    private func projectStats(_ project: ModrinthProjectDetail) -> some View {
        HStack(spacing: ModrinthProjectDetailConstants.spacing) {
            Label("\(project.downloads)", systemImage: "arrow.down.circle")
            Label("\(project.followers)", systemImage: "heart")

            FlowLayout(spacing: ModrinthProjectDetailConstants.categorySpacing) {
                ForEach(project.categories, id: \.self) {
                    CategoryTag(text: $0)
                }
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Project Content
    private func projectContent(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: ModrinthProjectDetailConstants.spacing) {
            descriptionView(project)
        }
        .padding(.horizontal, ModrinthProjectDetailConstants.padding)
        .padding(.bottom, ModrinthProjectDetailConstants.spacing)
    }

    private func descriptionView(_ project: ModrinthProjectDetail) -> some View {
        MixedMarkdownView(project.body)
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: ModrinthProjectDetailConstants.spacing) {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ModrinthProjectDetailConstants.padding)
    }
}

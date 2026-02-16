import SwiftUI

public struct ContributorsView: View {
    @StateObject private var viewModel = ContributorsViewModel()
    @State private var staticContributors: [StaticContributor] = []
    @State private var staticContributorsLoaded = false
    @State private var staticContributorsLoadFailed = false
    private let gitHubService = GitHubService.shared

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if viewModel.isLoading {
                    loadingView
                } else {
                    contributorsContent
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            // Re-fetch GitHub contributor data every time you open it
            Task {
                await viewModel.fetchContributors()
            }
            // Static contributor data is reloaded every time it is opened
            loadStaticContributors()
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

    // MARK: - Contributors Content
    private var contributorsContent: some View {
        LazyVStack(spacing: 16) {
            // GitHub contributor list
            if !viewModel.contributors.isEmpty {
                contributorsList
            }
            // Static contributor list (only displayed if loaded successfully)
            if staticContributorsLoaded && !staticContributorsLoadFailed {
                staticContributorsList
            }
        }
    }

    // MARK: - Static Contributors List
    private var staticContributorsList: some View {
        VStack(spacing: 0) {
            Text("Core Contributors")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(staticContributors.indices, id: \.self) { index in
                staticContributorRow(staticContributors[index])
                    .id("static-\(index)")

                if index < staticContributors.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Contributors List
    private var contributorsList: some View {
        VStack(spacing: 0) {
            // GitHub contributor titles
            Text("GitHub Contributors")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            // top contributors
            if !viewModel.topContributors.isEmpty {
                ForEach(
                    Array(viewModel.topContributors.enumerated()),
                    id: \.element.id
                ) { index, contributor in
                    ContributorCardView(
                        contributor: contributor,
                        isTopContributor: true,
                        rank: index + 1,
                        contributionsText: String(
                            format: String(localized: "\(viewModel.formatContributions(contributor.contributions)) contributions")
                        )
                    )
                    .id("top-\(contributor.id)")

                    if index < viewModel.topContributors.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }

                if !viewModel.otherContributors.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }

            // Other contributors
            ForEach(
                Array(viewModel.otherContributors.enumerated()),
                id: \.element.id
            ) { index, contributor in
                ContributorCardView(
                    contributor: contributor,
                    isTopContributor: false,
                    rank: index + viewModel.topContributors.count + 1,
                    contributionsText: String(
                        format: String(localized: "\(viewModel.formatContributions(contributor.contributions)) contributions")
                    )
                )
                .id("other-\(contributor.id)")

                if index < viewModel.otherContributors.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Static Contributor Row
    private func staticContributorRow(
        _ contributor: StaticContributor
    ) -> some View {
        StaticContributorCardView(contributor: contributor)
    }
    // MARK: - Load Static Contributors
    private func loadStaticContributors() {
        // reset state
        staticContributorsLoaded = false
        staticContributorsLoadFailed = false
        Task {
            do {
                let contributorsData: ContributorsData = try await gitHubService.fetchStaticContributors()

                await MainActor.run {
                    staticContributors = contributorsData.contributors.map { contributorData in
                        StaticContributor(
                            name: contributorData.name,
                            url: contributorData.url,
                            avatar: contributorData.avatar,
                            contributions: contributorData.contributions.compactMap {
                                Contribution(rawValue: "contributor.contribution.\($0)")
                            }
                        )
                    }
                    staticContributorsLoaded = true
                    staticContributorsLoadFailed = false
                    Logger.shared.info(
                        "Successfully loaded",
                        staticContributors.count,
                        "contributors from GitHubService"
                    )
                }
            } catch {
                Logger.shared.error("Failed to load contributors from GitHubService:", error)
                await MainActor.run {
                    staticContributorsLoadFailed = true
                }
            }
        }
    }

    // MARK: - Clear Static Contributors Data
    private func clearStaticContributorsData() {
        staticContributors = []
        staticContributorsLoaded = false
        staticContributorsLoadFailed = false
        Logger.shared.info("Static contributors data cleared")
    }

    /// Clean all data
    private func clearAllData() {
        clearStaticContributorsData()
        // Clean up ViewModel’s contributor data and release memory
        viewModel.clearContributors()
        // Clean image cache and free up memory
        ContributorAvatarCache.shared.clearCache()
        StaticContributorAvatarCache.shared.clearCache()
        Logger.shared.info("All contributors data cleared")
    }
}

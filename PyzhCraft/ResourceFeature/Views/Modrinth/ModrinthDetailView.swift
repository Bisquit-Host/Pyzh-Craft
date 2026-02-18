import SwiftUI

// MARK: - Main View
struct ModrinthDetailView: View {
    // MARK: - Properties
    let query: String
    @Binding var selectedVersions: [String]
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpact: [String]
    @Binding var selectedProjectId: String?
    @Binding var selectedLoader: [String]
    let gameInfo: GameVersionInfo?
    @Binding var selectedItem: SidebarItem
    @Binding var gameType: Bool
    let header: AnyView?
    @Binding var scannedDetailIds: Set<String> // detailId Set of scanned resources for quick lookup
    @Binding var dataSource: DataSource

    @StateObject private var viewModel = ModrinthSearchViewModel()
    @State private var hasLoaded = false
    @Binding var searchText: String
    @State private var searchTimer: Timer?
    @State private var currentPage: Int = 1
    @State private var lastSearchParams = ""
    @State private var error: GlobalError?

    init(
        query: String,
        selectedVersions: Binding<[String]>,
        selectedCategories: Binding<[String]>,
        selectedFeatures: Binding<[String]>,
        selectedResolutions: Binding<[String]>,
        selectedPerformanceImpact: Binding<[String]>,
        selectedProjectId: Binding<String?>,
        selectedLoader: Binding<[String]>,
        gameInfo: GameVersionInfo?,
        selectedItem: Binding<SidebarItem>,
        gameType: Binding<Bool>,
        header: AnyView? = nil,
        scannedDetailIds: Binding<Set<String>> = .constant([]),
        dataSource: Binding<DataSource> = .constant(.modrinth),
        searchText: Binding<String> = .constant("")
    ) {
        self.query = query
        _selectedVersions = selectedVersions
        _selectedCategories = selectedCategories
        _selectedFeatures = selectedFeatures
        _selectedResolutions = selectedResolutions
        _selectedPerformanceImpact = selectedPerformanceImpact
        _selectedProjectId = selectedProjectId
        _selectedLoader = selectedLoader
        self.gameInfo = gameInfo
        _selectedItem = selectedItem
        _gameType = gameType
        self.header = header
        _scannedDetailIds = scannedDetailIds
        _dataSource = dataSource
        _searchText = searchText
    }

    private var searchKey: String {
        [
            query,
            selectedVersions.joined(separator: ","),
            selectedCategories.joined(separator: ","),
            selectedFeatures.joined(separator: ","),
            selectedResolutions.joined(separator: ","),
            selectedPerformanceImpact.joined(separator: ","),
            selectedLoader.joined(separator: ","),
            String(gameType),
            dataSource.rawValue,
        ].joined(separator: "|")
    }

    private var hasMoreResults: Bool {
        viewModel.results.count < viewModel.totalHits
    }

    // MARK: - Body
    var body: some View {
        List {
            if let header {
                header
                    .listRowSeparator(.hidden)
            }
            listContent
            if viewModel.isLoadingMore {
                loadingMoreIndicator
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if showsLoadingOverlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.clear)
            }
        }
        .task {
            if gameType {
                await initialLoadIfNeeded()
            }
        }
        // Search again when filter conditions change
        .onChange(of: selectedVersions) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedCategories) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedFeatures) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedResolutions) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedPerformanceImpact) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedLoader) {
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedProjectId) { _, _ in
            // There is no need to refresh the details page after closing it, just use the cached data
            // If a status update is required (such as an installed tag), the view updates automatically
        }
        .onChange(of: dataSource) { _, _ in
            // Reset state and trigger new search when switching data sources
            hasLoaded = false
            resetPagination()
            searchText = ""
            lastSearchParams = ""
            error = nil
            triggerSearch()
        }
        .onChange(of: query) { _, _ in
            // Reset state and trigger new search when switching query type
            hasLoaded = false
            resetPagination()
            searchText = ""
            triggerSearch()
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search Resources"
        )
        .onChange(of: searchText) { oldValue, newValue in
            // Optimization: only trigger anti-shake search when the search text actually changes
            if oldValue != newValue {
                resetPagination()
                debounceSearch()
            }
        }
        .alert("Search Failed", isPresented: .constant(error != nil)) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.chineseMessage)
            }
        }
        .onDisappear {
            // Reset the state when the page disappears to ensure that it can be loaded correctly the next time you enter (use cache or network request)
            hasLoaded = false
            resetPagination()
        }
    }

    // MARK: - Private Methods
    private func initialLoadIfNeeded() async {
        if !hasLoaded {
            hasLoaded = true
            resetPagination()
            await performSearchWithErrorHandling(page: 1, append: false)
        }
    }

    private func triggerSearch() {
        Task {
            await performSearchWithErrorHandling(page: 1, append: false)
        }
    }

    private func debounceSearch() {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: false
        ) { _ in
            Task {
                await performSearchWithErrorHandling(page: 1, append: false)
            }
        }
    }

    private func performSearchWithErrorHandling(
        page: Int,
        append: Bool
    ) async {
        do {
            try await performSearchThrowing(page: page, append: append)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("搜索失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            await MainActor.run {
                self.error = globalError
            }
        }
    }

    private func performSearchThrowing(page: Int, append: Bool) async throws {
        let params = buildSearchParamsKey(page: page)

        if params == lastSearchParams {
            // Exact duplicate, no request
            return
        }

        guard !query.isEmpty else {
            throw GlobalError.validation(
                i18nKey: "Query Type Empty",
                level: .notification
            )
        }

        lastSearchParams = params
        if !append {
            viewModel.beginNewSearch()
        }
        await viewModel.search(
            query: searchText,
            projectType: query,
            versions: selectedVersions,
            categories: selectedCategories,
            features: selectedFeatures,
            resolutions: selectedResolutions,
            performanceImpact: selectedPerformanceImpact,
            loaders: selectedLoader,
            page: page,
            append: append,
            dataSource: dataSource
        )
    }

    // MARK: - Result List
    @ViewBuilder private var listContent: some View {
        Group {
            if let error {
                newErrorView(error)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else if hasLoaded && viewModel.results.isEmpty {
                emptyResultView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.results, id: \.projectId) { mod in
                    ModrinthDetailCardView(
                        project: mod,
                        selectedVersions: selectedVersions,
                        selectedLoaders: selectedLoader,
                        gameInfo: gameInfo,
                        query: query,
                        type: true,
                        selectedItem: $selectedItem,
                        scannedDetailIds: $scannedDetailIds
                    )
                    .padding(.vertical, ModrinthConstants.UIConstants.verticalPadding)
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                    )
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProjectId = mod.projectId
                        if let type = ResourceType(rawValue: query) {
                            selectedItem = .resource(type)
                        }
                    }
                    .onAppear {
                        loadNextPageIfNeeded(currentItem: mod)
                    }
                }
            }
        }
    }

    private func loadNextPageIfNeeded(currentItem mod: ModrinthProject) {
        guard hasMoreResults, !viewModel.isLoading, !viewModel.isLoadingMore else {
            return
        }
        guard
            let index = viewModel.results.firstIndex(where: { $0.projectId == mod.projectId })
        else { return }

        let thresholdIndex = max(viewModel.results.count - 5, 0)
        if index >= thresholdIndex {
            currentPage += 1
            let nextPage = currentPage
            Task {
                await performSearchWithErrorHandling(page: nextPage, append: true)
            }
        }
    }

    private func resetPagination() {
        currentPage = 1
        lastSearchParams = ""
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Clean up search timer to avoid memory leaks
        searchTimer?.invalidate()
        searchTimer = nil
        // Clean ViewModel data
        viewModel.clearResults()
        // Clean status data
        searchText = ""
        currentPage = 1
        lastSearchParams = ""
        error = nil
        hasLoaded = false
    }

    /// Clear data but keep search text (used when returning from details page)
    private func clearDataExceptSearchText() {
        // Clean up search timer to avoid memory leaks
        searchTimer?.invalidate()
        searchTimer = nil
        // Clean ViewModel data
        viewModel.clearResults()
        // Clean state data but keep search text
        currentPage = 1
        lastSearchParams = ""
        error = nil
        hasLoaded = false
    }

    private func buildSearchParamsKey(page: Int) -> String {
        [
            query,
            selectedVersions.joined(separator: ","),
            selectedCategories.joined(separator: ","),
            selectedFeatures.joined(separator: ","),
            selectedResolutions.joined(separator: ","),
            selectedPerformanceImpact.joined(separator: ","),
            selectedLoader.joined(separator: ","),
            String(gameType),
            searchText,
            "page:\(page)",
            dataSource.rawValue,
        ].joined(separator: "|")
    }

    private var loadingMoreIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var showsLoadingOverlay: Bool {
        viewModel.isLoading && viewModel.results.isEmpty && error == nil
    }
}

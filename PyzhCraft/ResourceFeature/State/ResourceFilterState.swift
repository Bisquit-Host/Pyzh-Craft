import SwiftUI

/// Resource filtering and list related status (observable)
final class ResourceFilterState: ObservableObject {
    
    // MARK: - Filter
    @Published var selectedVersions: [String] = []
    @Published var selectedLicenses: [String] = []
    @Published var selectedCategories: [String] = []
    @Published var selectedFeatures: [String] = []
    @Published var selectedResolutions: [String] = []
    @Published var selectedPerformanceImpact: [String] = []
    @Published var selectedLoaders: [String] = []
    @Published var sortIndex: String = AppConstants.modrinthIndex
    
    // MARK: - Paging and Tab
    @Published var versionCurrentPage: Int = 1
    @Published var versionTotal: Int = 0
    @Published var selectedTab: Int = 0
    
    // MARK: - Data sources and searches
    @Published var dataSource: DataSource
    @Published var searchText = ""
    @Published var localResourceFilter: LocalResourceFilter = .all
    
    init(dataSource: DataSource? = nil) {
        self.dataSource = dataSource ?? GameSettingsManager.shared.defaultAPISource
    }
    
    // MARK: - Convenience method
    
    /// Clear all filtering and paging (retain dataSource / searchText, etc. and can be expanded here as needed)
    func clearFiltersAndPagination() {
        selectedVersions.removeAll()
        selectedLicenses.removeAll()
        selectedCategories.removeAll()
        selectedFeatures.removeAll()
        selectedResolutions.removeAll()
        selectedPerformanceImpact.removeAll()
        selectedLoaders.removeAll()
        sortIndex = AppConstants.modrinthIndex
        selectedTab = 0
        versionCurrentPage = 1
        versionTotal = 0
    }
    
    /// Clear search text only
    func clearSearchText() {
        searchText = ""
    }
    
    // MARK: - Bindings (used when subviews require Binding)
    
    var selectedVersionsBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedVersions ?? [] }, set: { [weak self] in self?.selectedVersions = $0 })
    }
    var selectedLicensesBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedLicenses ?? [] }, set: { [weak self] in self?.selectedLicenses = $0 })
    }
    var selectedCategoriesBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedCategories ?? [] }, set: { [weak self] in self?.selectedCategories = $0 })
    }
    var selectedFeaturesBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedFeatures ?? [] }, set: { [weak self] in self?.selectedFeatures = $0 })
    }
    var selectedResolutionsBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedResolutions ?? [] }, set: { [weak self] in self?.selectedResolutions = $0 })
    }
    var selectedPerformanceImpactBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedPerformanceImpact ?? [] }, set: { [weak self] in self?.selectedPerformanceImpact = $0 })
    }
    var selectedLoadersBinding: Binding<[String]> {
        Binding(get: { [weak self] in self?.selectedLoaders ?? [] }, set: { [weak self] in self?.selectedLoaders = $0 })
    }
    var sortIndexBinding: Binding<String> {
        Binding(get: { [weak self] in self?.sortIndex ?? AppConstants.modrinthIndex }, set: { [weak self] in self?.sortIndex = $0 })
    }
    var versionCurrentPageBinding: Binding<Int> {
        Binding(get: { [weak self] in self?.versionCurrentPage ?? 1 }, set: { [weak self] in self?.versionCurrentPage = $0 })
    }
    var versionTotalBinding: Binding<Int> {
        Binding(get: { [weak self] in self?.versionTotal ?? 0 }, set: { [weak self] in self?.versionTotal = $0 })
    }
    var selectedTabBinding: Binding<Int> {
        Binding(get: { [weak self] in self?.selectedTab ?? 0 }, set: { [weak self] in self?.selectedTab = $0 })
    }
    var dataSourceBinding: Binding<DataSource> {
        Binding(get: { [weak self] in self?.dataSource ?? .modrinth }, set: { [weak self] in self?.dataSource = $0 })
    }
    var searchTextBinding: Binding<String> {
        Binding(get: { [weak self] in self?.searchText ?? "" }, set: { [weak self] in self?.searchText = $0 })
    }
    var localResourceFilterBinding: Binding<LocalResourceFilter> {
        Binding(get: { [weak self] in self?.localResourceFilter ?? .all }, set: { [weak self] in self?.localResourceFilter = $0 })
    }
}

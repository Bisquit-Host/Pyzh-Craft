import SwiftUI

// MARK: - CategoryContent
struct CategoryContentView: View {
    // MARK: - Properties
    let project: String
    @StateObject private var viewModel: CategoryContentViewModel
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpacts: [String]
    @Binding var selectedVersions: [String]
    @Binding var selectedLoaders: [String]
    let type: String
    let gameVersion: String?
    let gameLoader: String?
    let dataSource: DataSource

    // MARK: - Initialization
    init(
        project: String,
        type: String,
        selectedCategories: Binding<[String]>,
        selectedFeatures: Binding<[String]>,
        selectedResolutions: Binding<[String]>,
        selectedPerformanceImpacts: Binding<[String]>,
        selectedVersions: Binding<[String]>,
        selectedLoaders: Binding<[String]>,
        gameVersion: String? = nil,
        gameLoader: String? = nil,
        dataSource: DataSource
    ) {
        self.project = project
        self.type = type
        self._selectedCategories = selectedCategories
        self._selectedFeatures = selectedFeatures
        self._selectedResolutions = selectedResolutions
        self._selectedPerformanceImpacts = selectedPerformanceImpacts
        self._selectedVersions = selectedVersions
        self._selectedLoaders = selectedLoaders
        self.gameVersion = gameVersion
        self.gameLoader = gameLoader
        self.dataSource = dataSource
        // Use globally shared ViewModel to avoid repeated creation and data loading
        self._viewModel = StateObject(
            wrappedValue: CategoryDataCacheManager.shared.getViewModel(for: project)
        )
    }

    // MARK: - Body
    var body: some View {
        VStack {
            if let error = viewModel.error {
                newErrorView(error)
            } else {
                if type == "resource" {
                    versionSection
                }
                categorySection
                projectSpecificSections
            }
        }
        .task {
            await loadDataWithErrorHandling()
            setupDefaultSelections()
        }
    }

    // MARK: - Setup Methods
    private func setupDefaultSelections() {
        if let gameVersion = gameVersion {
            selectedVersions = [gameVersion]
        }
        if let gameLoader = gameLoader {
            if project != "shader" {
                selectedLoaders = [gameLoader]
            } else {
                selectedLoaders = []
            }
        }
    }

    // MARK: - Error Handling
    private func loadDataWithErrorHandling() async {
        do {
            try await loadDataThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("加载分类数据失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            await MainActor.run {
                viewModel.setError(globalError)
            }
        }
    }

    private func loadDataThrowing() async throws {
        guard !project.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目类型不能为空",
                i18nKey: "Project Type Empty",
                level: .notification
            )
        }

        await viewModel.loadData()
    }

    // MARK: - Section Views
    private var categorySection: some View {
        CategorySectionView(
            title: "Category",
            items: viewModel.categories.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedCategories,
            isLoading: viewModel.isLoading
        )
    }

    private var versionSection: some View {
        CategorySectionView(
            title: "Versions",
            items: viewModel.versions.map {
                FilterItem(id: $0.id, name: $0.id)
            },
            selectedItems: $selectedVersions,
            isLoading: viewModel.isLoading,
            isVersionSection: true
        )
    }

    private var loaderSection: some View {
        CategorySectionView(
            title: "Loader",
            items: filteredLoaders.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedLoaders,
            isLoading: viewModel.isLoading
        )
    }

    private var projectSpecificSections: some View {
        Group {
            switch project {
            case ProjectType.modpack, ProjectType.mod:
                if type == "resource" {
                    loaderSection
                }
                environmentSection
            case ProjectType.resourcepack:
                resourcePackSections
            case ProjectType.shader:
                if dataSource == .modrinth {
                    loaderSection
                }
                shaderSections
            default:
                EmptyView()
            }
        }
    }

    private var environmentSection: some View {
        CategorySectionView(
            title: "Environment",
            items: environmentItems,
            selectedItems: $selectedFeatures,
            isLoading: viewModel.isLoading
        )
    }

    private var resourcePackSections: some View {
        Group {
            CategorySectionView(
                title: "Behavior",
                items: viewModel.features.map {
                    FilterItem(id: $0.name, name: $0.name)
                },
                selectedItems: $selectedFeatures,
                isLoading: viewModel.isLoading
            )
            CategorySectionView(
                title: "Resolutions",
                items: viewModel.resolutions.map {
                    FilterItem(id: $0.name, name: $0.name)
                },
                selectedItems: $selectedResolutions,
                isLoading: viewModel.isLoading
            )
        }
    }

    private var shaderSections: some View {

        Group {
            // The CurseForge data source does not support performance requirements filtering and this section is not displayed under the CF tag
            if dataSource == .modrinth {
                CategorySectionView(
                    title: "Behavior",
                    items: viewModel.features.map {
                        FilterItem(id: $0.name, name: $0.name)
                    },
                    selectedItems: $selectedFeatures,
                    isLoading: viewModel.isLoading
                )
                CategorySectionView(
                    title: "Performance",
                    items: viewModel.performanceImpacts.map {
                        FilterItem(id: $0.name, name: $0.name)
                    },
                    selectedItems: $selectedPerformanceImpacts,
                    isLoading: viewModel.isLoading
                )
            }
        }
    }

    // MARK: - Computed Properties
    private var filteredLoaders: [Loader] {
        viewModel.loaders.filter {
            $0.supported_project_types.contains(project)
        }
    }

    private var environmentItems: [FilterItem] {
        [
            FilterItem(id: AppConstants.EnvironmentTypes.client, name: "Client".localized()),
            FilterItem(id: AppConstants.EnvironmentTypes.server, name: "Server".localized()),
        ]
    }
}

import SwiftUI

// MARK: - Version Grouped View
/// Version group display component, used to display the version list grouped by version series
struct VersionGroupedView: View {
    // MARK: - Properties
    let items: [FilterItem]
    @Binding var selectedItems: [String]
    let onItemTap: (String) -> Void
    var isMultiSelect = true  // Whether to support multiple selection, the default is true

    // Optional binding for radio mode
    @Binding var selectedItem: String?

    // MARK: - Initializers
    /// Multiple selection mode initialization
    init(items: [FilterItem], selectedItems: Binding<[String]>, onItemTap: @escaping (String) -> Void) {
        self.items = items
        self._selectedItems = selectedItems
        self.onItemTap = onItemTap
        self.isMultiSelect = true
        self._selectedItem = .constant(nil)
    }

    /// Radio mode initialization
    init(items: [FilterItem], selectedItem: Binding<String?>, onItemTap: @escaping (String) -> Void) {
        self.items = items
        self._selectedItem = selectedItem
        self.onItemTap = onItemTap
        self.isMultiSelect = false
        self._selectedItems = .constant([])
    }

    // MARK: - Constants
    private enum Constants {
        static let groupSpacing: CGFloat = 8
        static let itemSpacing: CGFloat = 4
        static let groupTitlePadding: CGFloat = 4
    }

    // MARK: - Body
    var body: some View {
        let groups = groupVersions(items)
        let sortedKeys = sortVersionKeys(groups.keys)

        ScrollView {
            VStack(alignment: .leading, spacing: Constants.groupSpacing) {
                ForEach(sortedKeys, id: \.self) {
                    versionGroupView(key: $0, items: groups[$0] ?? [])
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Private Views
    @ViewBuilder
    private func versionGroupView(key: String, items: [FilterItem]) -> some View {
        VStack(alignment: .leading, spacing: Constants.itemSpacing) {
            // Group title
            Text(key)
                .font(.headline.bold())
                .foregroundColor(.primary)
                .padding(.top, Constants.groupTitlePadding)

            // version item
            FlowLayout {
                ForEach(items) { item in
                    FilterChip(
                        title: item.name,
                        isSelected: isSelected(item.id)
                    ) {
                        onItemTap(item.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helper Methods
    /// Determine whether the item is selected
    private func isSelected(_ itemId: String) -> Bool {
        if isMultiSelect {
            selectedItems.contains(itemId)
        } else {
            selectedItem == itemId
        }
    }

    /// Group version items by major version number
    private func groupVersions(_ items: [FilterItem]) -> [String: [FilterItem]] {
        Dictionary(grouping: items) { item in
            let components = item.name.split(separator: ".")
            if components.count >= 2 {
                return "\(components[0]).\(components[1])"
            } else {
                return item.name
            }
        }
    }

    /// Sort version keys (latest version first)
    private func sortVersionKeys(_ keys: Dictionary<String, [FilterItem]>.Keys) -> [String] {
        keys.sorted { key1, key2 in
            let components1 = key1.split(separator: ".").compactMap { Int($0) }
            let components2 = key2.split(separator: ".").compactMap { Int($0) }
            return components1.lexicographicallyPrecedes(components2)
        }
        .reversed()
    }
}

import SwiftUI

struct LoadersSection: View {
    let loaders: [String]

    var body: some View {
        GenericSectionView(
            title: "Mod Loaders:",
            items: loaders.map { IdentifiableString(id: $0) },
            isLoading: false
        ) { item in
            VersionTag(version: item.id)
        }
    }
}

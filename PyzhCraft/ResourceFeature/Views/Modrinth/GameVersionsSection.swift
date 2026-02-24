import SwiftUI

struct GameVersionsSection: View {
    let versions: [String]

    var body: some View {
        GenericSectionView(
            title: "Versions:",
            items: versions.map { IdentifiableString(id: $0) },
            isLoading: false,
            maxItems: ModrinthProjectContentConstants.maxVisibleVersions
        ) { item in
            VersionTag(version: item.id)
        } overflowContentBuilder: { _ in
            AnyView(
                GameVersionsPopover(versions: versions)
            )
        }
    }
}

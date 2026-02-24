import SwiftUI

struct GameVersionsPopover: View {
    let versions: [String]

    var body: some View {
        VersionGroupedView(
            items: versions.map { FilterItem(id: $0, name: $0) },
            selectedItems: .constant([])
        ) { _ in
        }
        .frame(
            width: ModrinthProjectContentConstants.popoverWidth,
            height: ModrinthProjectContentConstants.popoverHeight
        )
    }
}

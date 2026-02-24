import SwiftUI

struct VersionTag: View {
    let version: String

    var body: some View {
        FilterChip(
            title: version,
            isSelected: false
        ) {}
    }
}

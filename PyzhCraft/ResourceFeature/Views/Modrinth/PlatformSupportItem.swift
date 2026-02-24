import SwiftUI

struct PlatformSupportItem: View {
    let icon: String
    let text: String

    var body: some View {
        FilterChip(
            title: text,
            isSelected: false,
            action: {},
            iconName: icon,
            iconColor: .secondary
        )
    }
}

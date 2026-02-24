import SwiftUI

struct CategoryTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, ModrinthProjectDetailConstants.categoryPadding)
            .padding(.vertical, ModrinthProjectDetailConstants.categoryVerticalPadding)
            .background(.gray.opacity(0.2))
            .cornerRadius(ModrinthProjectDetailConstants.categoryCornerRadius)
    }
}

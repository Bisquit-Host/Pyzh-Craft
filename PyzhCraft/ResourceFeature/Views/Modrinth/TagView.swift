import SwiftUI

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, ModrinthConstants.UIConstants.tagHorizontalPadding)
            .padding(.vertical, ModrinthConstants.UIConstants.tagVerticalPadding)
            .background(.gray.opacity(0.15))
            .cornerRadius(ModrinthConstants.UIConstants.tagCornerRadius)
    }
}

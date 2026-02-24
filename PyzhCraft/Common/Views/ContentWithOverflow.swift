import SwiftUI

// MARK: - Content With Overflow
struct ContentWithOverflow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let maxHeight: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        maxHeight: CGFloat = SectionViewConstants.defaultMaxHeight,
        verticalPadding: CGFloat = SectionViewConstants.defaultVerticalPadding,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.maxHeight = maxHeight
        self.verticalPadding = verticalPadding
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(items) {
                content($0)
            }
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, verticalPadding)
        .padding(.bottom, verticalPadding)
    }
}

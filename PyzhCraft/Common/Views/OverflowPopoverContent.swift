import SwiftUI

// MARK: - Overflow Popover Content
struct OverflowPopoverContent<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let maxHeight: CGFloat
    let width: CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        maxHeight: CGFloat = SectionViewConstants.defaultPopoverMaxHeight,
        width: CGFloat = SectionViewConstants.defaultPopoverWidth,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.maxHeight = maxHeight
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                FlowLayout {
                    ForEach(items) {
                        content($0)
                    }
                }
                .padding()
            }
            .frame(maxHeight: maxHeight)
        }
        .frame(width: width)
    }
}

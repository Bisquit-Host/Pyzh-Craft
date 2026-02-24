import SwiftUI

// MARK: - Loading Placeholder
struct LoadingPlaceholder: View {
    let count: Int
    let iconName: String?
    let maxHeight: CGFloat
    let verticalPadding: CGFloat
    let maxTextWidth: CGFloat?
    let verticalPaddingForChip: CGFloat

    init(
        count: Int = SectionViewConstants.defaultPlaceholderCount,
        iconName: String? = nil,
        maxHeight: CGFloat = SectionViewConstants.defaultMaxHeight,
        verticalPadding: CGFloat = SectionViewConstants.defaultVerticalPadding,
        maxTextWidth: CGFloat? = 150,
        verticalPaddingForChip: CGFloat = 4
    ) {
        self.count = count
        self.iconName = iconName
        self.maxHeight = maxHeight
        self.verticalPadding = verticalPadding
        self.maxTextWidth = maxTextWidth
        self.verticalPaddingForChip = verticalPaddingForChip
    }

    var body: some View {
        ScrollView {
            FlowLayout {
                ForEach(0..<count, id: \.self) { _ in
                    FilterChip(
                        title: "Loading",
                        iconName: iconName,
                        isLoading: true,
                        verticalPadding: verticalPaddingForChip,
                        maxTextWidth: maxTextWidth
                    )
                    .redacted(reason: .placeholder)
                }
            }
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, verticalPadding)
    }
}

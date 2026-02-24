import SwiftUI

// MARK: - Constants
enum SectionViewConstants {
    // Layout constants
    static let defaultMaxHeight: CGFloat = 235
    static let defaultVerticalPadding: CGFloat = 4
    static let defaultHeaderBottomPadding: CGFloat = 4

    // placeholder constant
    static let defaultPlaceholderCount: Int = 5

    // Pop-up window constants
    static let defaultPopoverWidth: CGFloat = 320
    static let defaultPopoverMaxHeight: CGFloat = 320

    // Item display constants
    static let defaultMaxItems: Int = 6
    static let defaultMaxWidth: CGFloat = 320

    // Chip related constants (used in row calculations)
    static let defaultChipPadding: CGFloat = 16
    static let defaultEstimatedCharWidth: CGFloat = 10
    static let defaultMaxRows: Int = 5
}

// MARK: - Array Extension
extension Array {
    /// Calculate visible and overflow items based on maximum number of items
    func computeVisibleAndOverflowItems(maxItems: Int) -> ([Element], [Element]) {
        let visibleItems = Array(prefix(maxItems))
        let overflowItems = Array(dropFirst(maxItems))
        return (visibleItems, overflowItems)
    }

    /// Calculate visible and overflow items based on row count and width (for CategorySectionView)
    func computeVisibleAndOverflowItemsByRows(
        maxRows: Int = SectionViewConstants.defaultMaxRows,
        maxWidth: CGFloat = SectionViewConstants.defaultMaxWidth,
        estimatedWidth: (Element) -> CGFloat
    ) -> ([Element], [Element]) {
        var rows: [[Element]] = []
        var currentRow: [Element] = []
        var currentRowWidth: CGFloat = 0

        for item in self {
            let itemWidth = estimatedWidth(item)

            if currentRowWidth + itemWidth > maxWidth, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [item]
                currentRowWidth = itemWidth
            } else {
                currentRow.append(item)
                currentRowWidth += itemWidth
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        let visibleRows = rows.prefix(maxRows)
        let visibleItems = visibleRows.flatMap { $0 }
        let overflowItems = Array(dropFirst(visibleItems.count))

        return (visibleItems, overflowItems)
    }
}

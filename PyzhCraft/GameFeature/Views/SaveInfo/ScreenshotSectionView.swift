import SwiftUI

// MARK: - Screenshot information area view
struct ScreenshotSectionView: View {
    // MARK: - Properties
    let screenshots: [ScreenshotInfo]
    let isLoading: Bool
    let gameName: String

    @State private var selectedScreenshot: ScreenshotInfo?

    // MARK: - Body
    var body: some View {
        GenericSectionView(
            title: "Screenshots",
            items: screenshots,
            isLoading: isLoading,
            iconName: "photo.fill"
        ) { screenshot in
            screenshotChip(for: screenshot)
        }
        .sheet(item: $selectedScreenshot) { screenshot in
            ScreenshotDetailView(screenshot: screenshot, gameName: gameName)
        }
    }

    // MARK: - Chip Builder
    private func screenshotChip(for screenshot: ScreenshotInfo) -> some View {
        FilterChip(
            title: screenshot.name,
            action: {
                selectedScreenshot = screenshot
            },
            iconName: "photo.fill",
            isLoading: false,
            maxTextWidth: 150
        )
    }
}

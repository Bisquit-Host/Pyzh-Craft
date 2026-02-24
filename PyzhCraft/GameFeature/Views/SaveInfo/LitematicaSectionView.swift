import SwiftUI

// MARK: - Litematica projected file area view
struct LitematicaSectionView: View {
    // MARK: - Properties
    let litematicaFiles: [LitematicaInfo]
    let isLoading: Bool
    let gameName: String

    @State private var selectedFile: LitematicaInfo?

    // MARK: - Body
    var body: some View {
        GenericSectionView(
            title: "Litematica",
            items: litematicaFiles,
            isLoading: isLoading,
            iconName: "square.stack.3d.up"
        ) { file in
            litematicaChip(for: file)
        }
        .sheet(item: $selectedFile) { file in
            LitematicaDetailSheetView(filePath: file.path, gameName: gameName)
        }
    }

    // MARK: - Chip Builder
    private func litematicaChip(for file: LitematicaInfo) -> some View {
        FilterChip(
            title: file.name,
            action: {
                selectedFile = file
            },
            iconName: "square.stack.3d.up",
            isLoading: false,
            verticalPadding: 6,
            maxTextWidth: 150
        )
    }
}

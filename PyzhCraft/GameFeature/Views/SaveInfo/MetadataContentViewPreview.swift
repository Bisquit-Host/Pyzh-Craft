import SwiftUI

struct MetadataContentViewPreview: View {
    let metadata: LitematicMetadata

    var body: some View {
        let sheetView = LitematicaDetailSheetView(filePath: URL(fileURLWithPath: "/tmp/test.litematic"), gameName: "Test Game")
        return sheetView.metadataContentView(metadata: metadata)
    }
}

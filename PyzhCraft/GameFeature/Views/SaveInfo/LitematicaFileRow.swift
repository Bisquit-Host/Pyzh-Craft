import SwiftUI

struct LitematicaFileRow: View {
    let file: LitematicaInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)

                if let author = file.author {
                    Text("Author: \(author)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let description = file.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let regionCount = file.regionCount {
                        Label(String(format: String(localized: "Regions: %d"), regionCount), systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let totalBlocks = file.totalBlocks {
                        Label(String(format: String(localized: "Blocks: %d"), totalBlocks), systemImage: "cube")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(file.path.deletingLastPathComponent())
            } label: {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

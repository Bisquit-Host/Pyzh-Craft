import SwiftUI

// MARK: - NBT structural view (maintains original nested structure)
struct NBTStructureView: View {
    let data: [String: Any]
    @State private var expandedKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(data.keys.sorted()), id: \.self) { key in
                if let value = data[key] {
                    NBTEntryView(
                        key: key,
                        value: value,
                        expandedKeys: $expandedKeys,
                        indentLevel: 0,
                        fullKey: key
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

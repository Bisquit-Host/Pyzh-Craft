import SwiftUI

struct ServerAddressRow: View {
    let server: ServerAddress

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)

                Text(server.fullAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(server.fullAddress, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

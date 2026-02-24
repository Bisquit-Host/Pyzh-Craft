import SwiftUI

struct PlatformSupportSection: View {
    let clientSide: String
    let serverSide: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Platform Support:")
                .font(.headline)
                .padding(.bottom, SectionViewConstants.defaultHeaderBottomPadding)

            ContentWithOverflow(
                items: [
                    IdentifiablePlatformItem(id: "client", icon: "laptopcomputer", text: supportLabel(for: clientSide)),
                    IdentifiablePlatformItem(id: "server", icon: "server.rack", text: supportLabel(for: serverSide)),
                ],
                maxHeight: SectionViewConstants.defaultMaxHeight,
                verticalPadding: SectionViewConstants.defaultVerticalPadding
            ) { item in
                PlatformSupportItem(icon: item.icon, text: item.text)
            }
        }
    }

    private func supportLabel(for value: String) -> String {
        switch value.lowercased() {
        case "required":
            String(localized: "Required")
        case "optional":
            String(localized: "Optional")
        case "unsupported":
            String(localized: "Unsupported")
        default:
            String(localized: "Unknown")
        }
    }
}

private struct IdentifiablePlatformItem: Identifiable {
    let id: String
    let icon: String
    let text: String
}

import SwiftUI

public struct PlayerSettingsView: View {
    public init() {}

    public var body: some View {
        HStack {
            Spacer()
            Form {
                Section(header: Text("Player Settings")) {
                    Text("Placeholder")
                }
            }
            // .frame(maxWidth: 500)
            Spacer()
        }
    }
}

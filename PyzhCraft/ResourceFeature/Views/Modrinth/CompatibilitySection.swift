import SwiftUI

struct CompatibilitySection: View {
    let project: ModrinthProjectDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !project.gameVersions.isEmpty {
                GameVersionsSection(versions: project.gameVersions)
            }

            if !project.loaders.isEmpty {
                LoadersSection(loaders: project.loaders)
            }

            PlatformSupportSection(
                clientSide: project.clientSide,
                serverSide: project.serverSide
            )
        }
    }
}

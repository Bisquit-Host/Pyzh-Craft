import SwiftUI

struct LinksSection: View {
    let project: ModrinthProjectDetail

    var body: some View {
        let links = [
            (project.issuesUrl, String(localized: "Report Issues")),
            (project.sourceUrl, String(localized: "View Source Code")),
            (project.wikiUrl, String(localized: "Visit Wiki")),
            (project.discordUrl, String(localized: "Join Discord")),
        ].compactMap { url, text in
            url.map { (text, $0) }
        }

        GenericSectionView(
            title: "Links",
            items: links.map { IdentifiableLink(id: $0.0, text: $0.0, url: $0.1) },
            isLoading: false
        ) { item in
            ProjectLink(text: item.text, url: item.url)
        }
    }
}

private struct IdentifiableLink: Identifiable {
    let id: String
    let text: String
    let url: String
}

import SwiftUI

struct DetailsSection: View, Equatable {
    let project: ModrinthProjectDetail

    private var publishedDateString: String {
        project.published.formatted(.relative(presentation: .named))
    }

    private var updatedDateString: String {
        project.updated.formatted(.relative(presentation: .named))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Details")
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                DetailRow(
                    label: "License",
                    value: (project.license?.name).map { $0.isEmpty ? String(localized: "Unknown") : $0 } ?? String(localized: "Unknown")
                )

                DetailRow(label: "Published Date", value: publishedDateString)
                DetailRow(label: "Updated Date", value: updatedDateString)
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.project.id == rhs.project.id &&
        lhs.project.license?.id == rhs.project.license?.id &&
        lhs.project.published == rhs.project.published &&
        lhs.project.updated == rhs.project.updated
    }
}

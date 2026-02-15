import SwiftUI

/// Contribution type label view
struct ContributionTagView: View {
    let contribution: Contribution

    var body: some View {
        Text(contribution.localizedString)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundColor(contribution.color)
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(lineWidth: 1)
                    .foregroundStyle(contribution.color)
                    .opacity(0.8)
            }
    }
}

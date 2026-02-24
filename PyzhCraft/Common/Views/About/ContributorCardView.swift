import SwiftUI

/// GitHub contributor card view
struct ContributorCardView: View {
    let contributor: GitHubContributor
    let isTopContributor: Bool
    let rank: Int
    let contributionsText: LocalizedStringKey
    
    var body: some View {
        Group {
            if let url = URL(string: contributor.htmlUrl) {
                Link(destination: url) {
                    contributorContent
                }
            } else {
                contributorContent
            }
        }
    }
    
    private var contributorContent: some View {
        HStack(spacing: 12) {
            // avatar
            ContributorAvatarView(avatarUrl: contributor.avatarUrl)
            
            // information
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contributor.login)
                        .font(
                            .system(
                                size: 13,
                                weight: isTopContributor
                                ? .semibold : .regular
                            )
                        )
                        .foregroundColor(.primary)
                    
                    if isTopContributor {
                        ContributorRankBadgeView(rank: rank)
                    }
                }
                
                HStack(spacing: 4) {
                    // Code tags (uniformly marked as code contributors)
                    ContributionTagView(contribution: .code)
                    
                    // Number of contributions
                    Text(contributionsText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // arrow
            Image("github-mark")
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .imageScale(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

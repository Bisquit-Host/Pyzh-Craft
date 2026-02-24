import SwiftUI

/// Static contributor card view
struct StaticContributorCardView: View {
    let contributor: StaticContributor
    
    var body: some View {
        Group {
            if !contributor.url.isEmpty, let url = URL(string: contributor.url) {
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
            // Avatar (emoji)
            StaticContributorAvatarView(avatar: contributor.avatar)
            
            // Information section
            VStack(alignment: .leading, spacing: 4) {
                // username
                Text(contributor.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                // Contribution tag line
                HStack(spacing: 6) {
                    ForEach(contributor.contributions, id: \.self) {
                        ContributionTagView(contribution: $0)
                    }
                    
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Show arrow icon if there is a URL
            if !contributor.url.isEmpty {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

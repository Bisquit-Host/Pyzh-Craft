import SwiftUI

/// Contribution type enum
enum Contribution: String, CaseIterable {
    case code = "contributor.contribution.code"
    case design = "contributor.contribution.design"
    case test = "contributor.contribution.test"
    case feedback = "contributor.contribution.feedback"
    case documentation = "contributor.contribution.documentation"
    case infra = "contributor.contribution.infra"

    var localizedString: String {
        rawValue.localized()
    }

    var color: Color {
        switch self {
        case .code: .blue
        case .design: .purple
        case .test: .green
        case .feedback: .orange
        case .documentation: .indigo
        case .infra: .red
        }
    }
}

/// static contributor
struct StaticContributor {
    let name: String
    let url: String
    let avatar: String
    let contributions: [Contribution]
}

/// JSON data model
struct ContributorsData: Codable {
    let contributors: [ContributorData]
}

struct ContributorData: Codable {
    let name: String
    let url: String
    let avatar: String
    let contributions: [String]
}

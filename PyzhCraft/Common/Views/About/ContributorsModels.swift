import SwiftUI

/// Contribution type enum
enum Contribution: String, CaseIterable {
    case code, design, test, feedback, documentation, infra
    
    var localizedString: LocalizedStringKey {
        switch self {
        case .code: "Code"
        case .design: "Design"
        case .test: "Test"
        case .feedback: "Feedback"
        case .documentation: "Documentation"
        case .infra: "Infra"
        }
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

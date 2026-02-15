import Foundation

// MARK: - GitHub Service
@MainActor
public class GitHubService: ObservableObject {

    public static let shared = GitHubService()

    // MARK: - Public Methods

    /// Get the list of repository contributors
    public func fetchContributors(perPage: Int = 50) async throws -> [GitHubContributor] {
        let url = URLConfig.API.GitHub.contributors(perPage: perPage)
        // Use a unified API client
        let data = try await APIClient.get(url: url)
        return try JSONDecoder().decode([GitHubContributor].self, from: data)
    }

    // MARK: - Static Contributors

    /// Get static contributor raw data (JSON)
    private func fetchStaticContributorsData() async throws -> Data {
        let url = URLConfig.API.GitHub.staticContributors()
        // Use a unified API client
        return try await APIClient.get(url: url)
    }

    /// Get the decoded data of static contributors
    public func fetchStaticContributors<T: Decodable>() async throws -> T {
        let data = try await fetchStaticContributorsData()
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Acknowledgements

    /// Get open source acknowledgments raw data (JSON)
    private func fetchAcknowledgementsData() async throws -> Data {
        let url = URLConfig.API.GitHub.acknowledgements()
        // Use a unified API client
        let headers = ["Accept": "application/json"]
        return try await APIClient.get(url: url, headers: headers)
    }

    /// Get open source acknowledgment decoded data
    public func fetchAcknowledgements<T: Decodable>() async throws -> T {
        let data = try await fetchAcknowledgementsData()
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Announcement

    /// Get announcement data
    /// - Parameters:
    ///   - version: application version number
    ///   - language: language code
    /// - Returns: announcement data, if it does not exist (404), return nil
    public func fetchAnnouncement(
        version: String,
        language: String
    ) async throws -> AnnouncementData? {
        let url = URLConfig.API.GitHub.announcement(
            version: version,
            language: language
        )

        // Use a unified API client
        let headers = ["Accept": "application/json"]
        let data = try await APIClient.get(url: url, headers: headers)

        let announcementResponse = try JSONDecoder().decode(
            AnnouncementResponse.self,
            from: data
        )

        guard announcementResponse.success else {
            throw GitHubServiceError.announcementNotSuccessful
        }

        return announcementResponse.data
    }
}

// MARK: - GitHubService Error

public enum GitHubServiceError: Error {
    case httpError(statusCode: Int)
    case invalidResponse, announcementNotSuccessful
}

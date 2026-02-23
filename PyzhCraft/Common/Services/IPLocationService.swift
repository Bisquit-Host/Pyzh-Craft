import Foundation

/// IP location service
/// Detect the country/region where the user’s IP is located
@MainActor
class IPLocationService: ObservableObject {
    static let shared = IPLocationService()

    private init() {}

    /// Check if it is a foreign IP (silent version)
    /// - Returns: Whether it is a foreign IP, if the detection fails, it returns false (allowing to add offline accounts)
    func isForeignIP() async -> Bool {
        do {
            return try await isForeignIPThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to detect IP location: \(globalError.chineseMessage)")
            // Fail silently and return false (allow adding offline accounts)
            return false
        }
    }

    /// Check whether it is a foreign IP (throws an exception version)
    /// - Returns: Whether it is a foreign IP
    /// - Throws: GlobalError when detection fails
    func isForeignIPThrowing() async throws -> Bool {
        // Request geolocation information
        let url = URLConfig.API.IPLocation.currentLocation
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        // Use performRequestWithResponse to get complete response information, including status code
        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        // Try to parse the response even if the status code is not 200 (as some APIs may return 429 but still include data in the response body)
        let locationResponse: IPLocationResponse
        do {
            locationResponse = try JSONDecoder().decode(IPLocationResponse.self, from: data)
        } catch {
            // If parsing fails, log the status code for debugging
            Logger.shared.error("Failed to parse IP geographical location response: HTTP \(httpResponse.statusCode), error: \(error.localizedDescription)")
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.shared.error("Response content: \(responseString)")
            }
            throw GlobalError.validation(
                i18nKey: "Failed to parse IP location response",
                level: .notification
            )
        }

        // If the status code is not 200, log a warning but continue processing (as there may still be valid data)
        if httpResponse.statusCode != 200 {
            Logger.shared.warning("IP Geolocation API returns non-200 status code: \(httpResponse.statusCode)")
        }

        // Check if the request was successful
        guard locationResponse.isSuccess else {
            let errorMessage = locationResponse.reason ?? "IP geolocation detection failed"
            Logger.shared.error("IP geolocation detection failed: \(errorMessage), country code: \(locationResponse.countryCode ?? "unknown")")
            throw GlobalError.network(
                i18nKey: "IP location detection failed",
                level: .notification
            )
        }

        Logger.shared.debug("IP geolocation detection completed: country code = \(locationResponse.countryCode ?? "unknown"), isForeign = \(locationResponse.isForeign)")

        return locationResponse.isForeign
    }
}

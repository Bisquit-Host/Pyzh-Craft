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
            Logger.shared.error("检测IP地理位置失败: \(globalError.chineseMessage)")
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
            Logger.shared.error("解析IP地理位置响应失败: HTTP \(httpResponse.statusCode), error: \(error.localizedDescription)")
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.shared.error("响应内容: \(responseString)")
            }
            throw GlobalError.validation(
                chineseMessage: "解析IP地理位置响应失败: \(error.localizedDescription)",
                i18nKey: "error.validation.ip_location_parse_failed",
                level: .notification
            )
        }

        // If the status code is not 200, log a warning but continue processing (as there may still be valid data)
        if httpResponse.statusCode != 200 {
            Logger.shared.warning("IP地理位置API返回非200状态码: \(httpResponse.statusCode)")
        }

        // Check if the request was successful
        guard locationResponse.isSuccess else {
            let errorMessage = locationResponse.reason ?? "IP地理位置检测失败"
            Logger.shared.error("IP地理位置检测失败: \(errorMessage), 国家代码: \(locationResponse.countryCode ?? "未知")")
            throw GlobalError.network(
                chineseMessage: errorMessage,
                i18nKey: "error.network.ip_location_failed",
                level: .notification
            )
        }

        Logger.shared.debug("IP地理位置检测完成: 国家代码 = \(locationResponse.countryCode ?? "未知"), 是否为国外 = \(locationResponse.isForeign)")

        return locationResponse.isForeign
    }
}

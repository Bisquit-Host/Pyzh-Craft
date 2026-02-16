import Foundation

/// Unified API client
enum APIClient {
    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,  // 4MB memory cache
            diskCapacity: 20 * 1024 * 1024,   // 20MB disk cache
            diskPath: nil
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    private static let contentTypeHeader = "Content-Type"
    private static let contentTypeJSON = "application/json"
    private static let httpMethodGET = "GET"
    private static let httpMethodPOST = "POST"

    /// Perform a GET request
    /// - Parameters:
    ///   - url: request URL
    ///   - headers: optional request headers
    /// - Returns: response data
    /// - Throws: GlobalError when the request fails
    static func get(
        url: URL,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethodGET

        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        return try await performRequest(request: request)
    }

    /// Perform a POST request
    /// - Parameters:
    ///   - url: request URL
    ///   - body: request body data
    ///   - headers: optional request headers (if Content-Type is included, the provided value will be used, otherwise it defaults to application/json)
    /// - Returns: response data
    /// - Throws: GlobalError when the request fails
    static func post(
        url: URL,
        body: Data? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethodPOST
        request.httpBody = body

        var needsContentType = false
        if body != nil {
            if let headers = headers {
                needsContentType = !headers.keys.contains { key in
                    key.localizedCaseInsensitiveCompare(contentTypeHeader) == .orderedSame
                }
            } else {
                needsContentType = true
            }
        }

        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        if needsContentType {
            request.setValue(contentTypeJSON, forHTTPHeaderField: contentTypeHeader)
        }

        return try await performRequest(request: request)
    }

    /// Execute the request and return the decoded object
    /// - Parameters:
    ///   - url: request URL
    ///   - method: HTTP method
    ///   - body: request body data
    ///   - headers: optional request headers
    ///   - decoder: JSON decoder (optional, shared decoder is used by default)
    /// - Returns: decoded object
    /// - Throws: GlobalError when the request fails
    static func request<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil,
        decoder: JSONDecoder? = nil
    ) async throws -> T {
        let data = try await requestData(
            url: url,
            method: method,
            body: body,
            headers: headers
        )
        return try (decoder ?? sharedDecoder).decode(T.self, from: data)
    }

    /// Execute the request and return the original data
    /// - Parameters:
    ///   - url: request URL
    ///   - method: HTTP method
    ///   - body: request body data
    ///   - headers: optional request headers
    /// - Returns: response data
    /// - Throws: GlobalError when the request fails
    static func requestData(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if body != nil && method == httpMethodPOST {
            request.setValue(contentTypeJSON, forHTTPHeaderField: contentTypeHeader)
        }

        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        return try await performRequest(request: request)
    }

    /// Execute request (internal method)
    /// - Parameter request: URLRequest
    /// - Returns: response data
    /// - Throws: GlobalError when the request fails
    private static func performRequest(request: URLRequest) async throws -> Data {
        let (data, response) = try await sharedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalError(type: .network, i18nKey: "Invalid response",
                level: .notification
            )
        }

        guard httpResponse.statusCode == 200 else {
            throw GlobalError(type: .network, i18nKey: "API request failed",
                level: .notification
            )
        }

        return data
    }

    /// - Parameter request: URLRequest
    /// - Returns: (data, HTTP response)
    /// - Throws: GlobalError when the request fails
    static func performRequestWithResponse(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await sharedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalError(type: .network, i18nKey: "Invalid response",
                level: .notification
            )
        }

        return (data, httpResponse)
    }
}

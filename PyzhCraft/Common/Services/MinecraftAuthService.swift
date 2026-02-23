import SwiftUI
import AppKit

class MinecraftAuthService: ObservableObject {
    static let shared = MinecraftAuthService()

    @Published var authState: AuthenticationState = .notAuthenticated
    @Published var isLoading = false
    @Published var deviceCodeInfo: MicrosoftDeviceCodeResponse?

    private let clientId = AppConstants.minecraftClientId
    private let scope = AppConstants.minecraftScope
    private let fallbackVerificationURL = URL(string: "https://microsoft.com/link") ?? URL(fileURLWithPath: "/")
    private var liveCookieHeader: String?

    private init() {}

    // MARK: - Authentication process (using Microsoft device code)
    @MainActor
    func startAuthentication() async {
        isLoading = true
        authState = .waitingForBrowserAuth
        deviceCodeInfo = nil
        liveCookieHeader = nil
        Logger.shared.info("Microsoft 设备码登录开始")

        do {
            let deviceCode = try await requestDeviceCode()
            deviceCodeInfo = deviceCode
            openDeviceCodePage(for: deviceCode)
            Logger.shared.info("已获取设备码，等待用户授权")

            let tokenResponse = try await pollForDeviceCodeToken(deviceCode: deviceCode)
            Logger.shared.info("设备码轮询成功，开始验证 Minecraft 账户")
            try await completeAuthentication(tokenResponse: tokenResponse)
        } catch is CancellationError {
            Logger.shared.info("用户取消了 Microsoft 认证")
            isLoading = false
            deviceCodeInfo = nil
            authState = .notAuthenticated
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Minecraft 认证失败: \(globalError.chineseMessage)")
            isLoading = false
            deviceCodeInfo = nil
            authState = .error(globalError.chineseMessage)
        }
    }

    private func openDeviceCodePage(for deviceCode: MicrosoftDeviceCodeResponse) {
        let verificationURL = URL(string: deviceCode.displayVerificationURL) ?? fallbackVerificationURL
        NSWorkspace.shared.open(verificationURL)
    }

    private func requestDeviceCode() async throws -> MicrosoftDeviceCodeResponse {
        let url = URLConfig.API.Authentication.deviceCode
        let bodyParameters = [
            "client_id": clientId,
            "scope": scope,
            "response_type": "device_code",
        ]
        let bodyData = encodeFormBody(bodyParameters)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        if let setCookieHeader = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            liveCookieHeader = setCookieHeader
                .split(separator: ";")
                .first
                .map(String.init)
        }

        guard httpResponse.statusCode == 200 else {
            if let oauthError = parseOAuthErrorResponse(from: data) {
                Logger.shared.error("Microsoft 设备码请求失败: \(oauthError.error)")
            }
            throw GlobalError.authentication(
                i18nKey: "Authentication failed",
                level: .notification
            )
        }

        do {
            let response = try JSONDecoder().decode(MicrosoftDeviceCodeResponse.self, from: data)
            Logger.shared.debug("设备码获取成功，过期时间: \(response.expiresIn)s")
            return response
        } catch {
            throw GlobalError.validation(
                i18nKey: "Token response parse failed",
                level: .notification
            )
        }
    }

    private enum DeviceCodePollingState {
        case waiting, slowDown, declined, expired, token(TokenResponse), failed
    }

    private func pollForDeviceCodeToken(deviceCode: MicrosoftDeviceCodeResponse) async throws -> TokenResponse {
        let expiresAt = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(deviceCode.interval ?? 5, 1)
        var attempt = 0

        while Date() < expiresAt {
            try Task.checkCancellation()

            let sleepNanoseconds = UInt64(interval) * 1_000_000_000
            try await Task.sleep(nanoseconds: sleepNanoseconds)
            attempt += 1

            let pollingState = try await pollDeviceCodeTokenOnce(deviceCode: deviceCode.deviceCode)
            switch pollingState {
            case .waiting:
                if attempt % 5 == 0 {
                    Logger.shared.debug("设备码轮询中，等待用户完成授权")
                }
                continue
            case .slowDown:
                interval += 5
                Logger.shared.debug("设备码轮询要求减速，新的轮询间隔: \(interval)s")
            case .declined:
                throw CancellationError()
            case .expired:
                throw GlobalError.authentication(
                    i18nKey: "Authentication failed, timed out",
                    level: .notification
                )
            case .token(let token):
                return token
            case .failed:
                throw GlobalError.authentication(
                    i18nKey: "Authentication failed",
                    level: .notification
                )
            }
        }

        throw GlobalError.authentication(
            i18nKey: "Authentication failed, timed out",
            level: .notification
        )
    }

    private func pollDeviceCodeTokenOnce(deviceCode: String) async throws -> DeviceCodePollingState {
        let url = URLConfig.API.Authentication.token
            .appending(queryItems: [
                URLQueryItem(name: "client_id", value: clientId)
            ])
        let bodyParameters = [
            "client_id": clientId,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]
        let bodyData = encodeFormBody(bodyParameters)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        if let liveCookieHeader, !liveCookieHeader.isEmpty {
            request.setValue(liveCookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        if let oauthError = parseOAuthErrorResponse(from: data) {
            switch oauthError.error {
            case "authorization_pending":
                return .waiting
            case "slow_down":
                return .slowDown
            case "authorization_declined":
                return .declined
            case "expired_token", "bad_verification_code":
                return .expired
            default:
                Logger.shared.error("Microsoft 设备码轮询失败: \(oauthError.error)")
                return .failed
            }
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.error("Microsoft 设备码轮询失败: HTTP \(httpResponse.statusCode)")
            return .failed
        }

        if let token = parseTokenResponse(from: data) {
            return .token(token)
        }

        throw GlobalError.validation(
            i18nKey: "Token response parse failed",
            level: .notification
        )
    }

    @MainActor
    private func completeAuthentication(tokenResponse: TokenResponse) async throws {
        authState = .processingAuthCode

        let xboxToken = try await getXboxLiveTokenThrowing(accessToken: tokenResponse.accessToken)
        let minecraftToken = try await getMinecraftTokenThrowing(
            xboxToken: xboxToken.token,
            uhs: xboxToken.displayClaims.xui.first?.uhs ?? ""
        )
        try await checkMinecraftOwnership(accessToken: minecraftToken)

        let minecraftTokenExpiration = JWTDecoder.getMinecraftTokenExpiration(from: minecraftToken)
        Logger.shared.info("Minecraft token过期时间: \(minecraftTokenExpiration)")

        let profile = try await getMinecraftProfileThrowing(
            accessToken: minecraftToken,
            authXuid: xboxToken.displayClaims.xui.first?.uhs ?? "",
            refreshToken: tokenResponse.refreshToken ?? ""
        )

        Logger.shared.info("Minecraft 认证成功，用户: \(profile.name)")
        isLoading = false
        deviceCodeInfo = nil
        authState = .authenticated(profile: profile)
    }

    private func encodeFormBody(_ params: [String: String]) -> Data? {
        let bodyString = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        return bodyString.data(using: .utf8)
    }

    private func parseOAuthErrorResponse(from data: Data) -> MicrosoftOAuthErrorResponse? {
        if let oauthError = try? JSONDecoder().decode(MicrosoftOAuthErrorResponse.self, from: data) {
            return oauthError
        }

        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else { return nil }
        guard let components = URLComponents(string: "?\(body)"),
              let queryItems = components.queryItems else { return nil }

        guard let error = queryItems.first(where: { $0.name == "error" })?.value else { return nil }
        let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value
        return MicrosoftOAuthErrorResponse(error: error, errorDescription: errorDescription)
    }

    private func parseTokenResponse(from data: Data) -> TokenResponse? {
        if let token = try? JSONDecoder().decode(TokenResponse.self, from: data) {
            return token
        }

        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else { return nil }
        guard let components = URLComponents(string: "?\(body)"),
              let queryItems = components.queryItems else { return nil }

        guard let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value else { return nil }
        let refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value
        let expiresIn = queryItems
            .first(where: { $0.name == "expires_in" })?
            .value
            .flatMap(Int.init)
        return TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    // MARK: - Get Xbox Live token (silent version)
    private func getXboxLiveToken(accessToken: String) async -> XboxLiveTokenResponse? {
        do {
            return try await getXboxLiveTokenThrowing(accessToken: accessToken)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Xbox Live 令牌失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    // MARK: - Get Xbox Live token (throws exception version)
    private func getXboxLiveTokenThrowing(accessToken: String) async throws -> XboxLiveTokenResponse {
        let url = URLConfig.API.Authentication.xboxLiveAuth

        let body: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "t=\(accessToken)",
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT",
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GlobalError.validation(
                i18nKey: "Xbox Live Request Serialize Failed",
                level: .notification
            )
        }

        // Use a unified API client
        let headers = ["Content-Type": "application/json"]
        let data = try await APIClient.post(url: url, body: bodyData, headers: headers)

        do {
            return try JSONDecoder().decode(XboxLiveTokenResponse.self, from: data)
        } catch {
            throw GlobalError.validation(
                i18nKey: "Xbox Live Token Parse Failed",
                level: .notification
            )
        }
    }

    // MARK: - Get Minecraft access token (silent version)
    private func getMinecraftToken(xboxToken: String, uhs: String) async -> String? {
        do {
            return try await getMinecraftTokenThrowing(xboxToken: xboxToken, uhs: uhs)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Minecraft 访问令牌失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    // MARK: - Get Minecraft access token (throws exception version)
    private func getMinecraftTokenThrowing(xboxToken: String, uhs: String) async throws -> String {
        // Get XSTS token
        let xstsUrl = URLConfig.API.Authentication.xstsAuth

        let xstsBody: [String: Any] = [
            "Properties": [
                "SandboxId": "RETAIL",
                "UserTokens": [xboxToken],
            ],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT",
        ]

        let xstsBodyData: Data
        do {
            xstsBodyData = try JSONSerialization.data(withJSONObject: xstsBody)
        } catch {
            throw GlobalError.validation(i18nKey: "XSTS Request Serialize Failed", level: .notification)
        }

        // Use a unified API client
        let xstsHeaders = ["Content-Type": "application/json"]
        let xstsData = try await APIClient.post(url: xstsUrl, body: xstsBodyData, headers: xstsHeaders)

        let xstsTokenResponse: XboxLiveTokenResponse
        do {
            xstsTokenResponse = try JSONDecoder().decode(XboxLiveTokenResponse.self, from: xstsData)
        } catch {
            throw GlobalError.validation(
                i18nKey: "XSTS Token Parse Failed",
                level: .notification
            )
        }

        // Get Minecraft access token
        Logger.shared.debug("开始获取 Minecraft 访问令牌")
        let minecraftUrl = URLConfig.API.Authentication.minecraftLogin

        let minecraftBody: [String: Any] = [
            "identityToken": "XBL3.0 x=\(uhs);\(xstsTokenResponse.token)"
        ]

        let minecraftBodyData: Data
        do {
            minecraftBodyData = try JSONSerialization.data(withJSONObject: minecraftBody)
        } catch {
            throw GlobalError.validation(
                i18nKey: "Minecraft Request Serialize Failed",
                level: .notification
            )
        }

        // Use unified API client (needs to handle non-200 status codes)
        var minecraftRequest = URLRequest(url: minecraftUrl)
        minecraftRequest.httpMethod = "POST"
        minecraftRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        minecraftRequest.timeoutInterval = 30.0
        minecraftRequest.httpBody = minecraftBodyData

        let (minecraftData, minecraftHttpResponse) = try await APIClient.performRequestWithResponse(request: minecraftRequest)

        guard minecraftHttpResponse.statusCode == 200 else {
            let statusCode = minecraftHttpResponse.statusCode
            Logger.shared.error("Minecraft 认证失败: HTTP \(statusCode)")

            // Provide more specific error information based on different status codes
            switch statusCode {
            case 401:
                throw GlobalError.authentication(
                    i18nKey: "Minecraft authentication failed: Xbox Live token is invalid or expired",
                    level: .notification
                )
            case 403:
                throw GlobalError.authentication(
                    i18nKey: "Minecraft authentication failed: This Microsoft account does not own Minecraft",
                    level: .notification
                )
            case 503:
                throw GlobalError.network(
                    i18nKey: "Minecraft authentication service is temporarily unavailable, please try again later",
                    level: .notification
                )
            case 429:
                throw GlobalError.network(
                    i18nKey: "Too many requests, please try again later",
                    level: .notification
                )
            default:
                throw GlobalError.download(
                    i18nKey: "Minecraft Token Failed",
                    level: .notification
                )
            }
        }

        let minecraftTokenResponse: TokenResponse
        do {
            minecraftTokenResponse = try JSONDecoder().decode(TokenResponse.self, from: minecraftData)
        } catch {
            throw GlobalError.validation(
                i18nKey: "Minecraft Token Parse Failed",
                level: .notification
            )
        }

        return minecraftTokenResponse.accessToken
    }

    // MARK: - Check Minecraft game ownership
    private func checkMinecraftOwnership(accessToken: String) async throws {
        let url = URLConfig.API.Authentication.minecraftEntitlements
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0

        // Use unified API client (needs to handle non-200 status codes)
        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode

            // Provide specific error information based on status code
            switch statusCode {
            case 401:
                throw GlobalError.authentication(
                    i18nKey: "Minecraft access token is invalid or expired",
                    level: .notification
                )
            case 403:
                throw GlobalError.authentication(
                    i18nKey: "This account has not purchased Minecraft, please log in with a Microsoft account that owns Minecraft",
                    level: .popup
                )
            default:
                throw GlobalError.download(
                    i18nKey: "Failed to check game ownership: HTTP \(String(statusCode))",
                    level: .notification
                )
            }
        }

        do {
            let entitlements = try JSONDecoder().decode(MinecraftEntitlementsResponse.self, from: data)

            // Check if you have the necessary game permissions
            let hasProductMinecraft = entitlements.items.contains { $0.name == MinecraftEntitlement.productMinecraft.rawValue }
            let hasGameMinecraft = entitlements.items.contains { $0.name == MinecraftEntitlement.gameMinecraft.rawValue }

            if !hasProductMinecraft || !hasGameMinecraft {
                throw GlobalError.authentication(
                    i18nKey: "This Microsoft account has not purchased Minecraft or has insufficient entitlements, please log in with an account that has purchased Minecraft",
                    level: .popup
                )
            }

            // Verification passed
        } catch let decodingError as DecodingError {
            throw GlobalError.validation(
                i18nKey: "Failed to parse game entitlements response: \(decodingError.localizedDescription)",
                level: .notification
            )
        } catch let globalError as GlobalError {
            // Rethrow GlobalError
            throw globalError
        } catch {
            throw GlobalError.validation(
                i18nKey: "Unknown error occurred while checking game ownership: \(error.localizedDescription)",
                level: .notification
            )
        }
    }

    // MARK: - Get Minecraft user profile
    private func getMinecraftProfileThrowing(accessToken: String, authXuid: String, refreshToken: String = "") async throws -> MinecraftProfileResponse {
        let url = URLConfig.API.Authentication.minecraftProfile
        // Use a unified API client
        let headers = ["Authorization": "Bearer \(accessToken)"]
        let data = try await APIClient.get(url: url, headers: headers)

        do {
            let profile = try JSONDecoder().decode(MinecraftProfileResponse.self, from: data)

            // accessToken, authXuid and refreshToken are not returned by API and need to be set manually
            return MinecraftProfileResponse(
                id: profile.id,
                name: profile.name,
                skins: profile.skins,
                capes: profile.capes,
                accessToken: accessToken,
                authXuid: authXuid,
                refreshToken: refreshToken
            )
        } catch {
            throw GlobalError.validation(
                i18nKey: "Minecraft Profile Parse Failed",
                level: .notification
            )
        }
    }

    // MARK: - Logout/cancel authentication
    @MainActor
    func logout() {
        authState = .notAuthenticated
        deviceCodeInfo = nil
        isLoading = false
    }

    // MARK: - Clean authentication data
    @MainActor
    func clearAuthenticationData() {
        authState = .notAuthenticated
        deviceCodeInfo = nil
        isLoading = false
    }
}

// MARK: - Token Validation and Refresh
extension MinecraftAuthService {
    // MARK: - Token verification and refresh related methods

    /// Refresh the token of the specified player (public interface)
    /// - Parameter player: Player who needs to refresh Token
    /// - Returns: refreshed player object
    @MainActor
    func refreshPlayerToken(for player: Player) async -> Result<Player, GlobalError> {
        isLoading = true
        defer { isLoading = false }

        do {
            let refreshedPlayer = try await validateAndRefreshPlayerTokenThrowing(for: player)
            Logger.shared.info("成功刷新玩家 \(player.name) 的 Token")
            return .success(refreshedPlayer)
        } catch let error as GlobalError {
            return .failure(error)
        } catch {
            let globalError = GlobalError.authentication(
                i18nKey: "Unknown error occurred while refreshing token: \(error.localizedDescription)",
                level: .popup
            )
            return .failure(globalError)
        }
    }

    /// Verify and try to refresh player token
    /// - Parameter player: player object
    /// - Returns: verified/refreshed player object
    /// - Throws: GlobalError when the operation fails
    func validateAndRefreshPlayerTokenThrowing(for player: Player) async throws -> Player {

        // If there is no access token, throw an error and ask to log in again
        guard !player.authAccessToken.isEmpty else {
            throw GlobalError.authentication(
                i18nKey: "Access token is missing, please log in again",
                level: .notification
            )
        }

        // Check whether the token expires based on tokenExpiresAt
        let isTokenExpired = await isTokenExpiredBasedOnTime(for: player)

        if !isTokenExpired {
            Logger.shared.debug("玩家 \(player.name) 的Token尚未过期，无需刷新")
            return player
        }

        Logger.shared.info("玩家 \(player.name) 的Token已过期，尝试刷新")

        // Token expires, try to refresh using refresh token
        guard !player.authRefreshToken.isEmpty else {
            throw GlobalError.authentication(
                i18nKey: "Login has expired, please re-login to this account",
                level: .popup
            )
        }

        // Refresh access token using refresh token
        let refreshedTokens = try await refreshTokenThrowing(refreshToken: player.authRefreshToken)

        // Get the complete authentication chain using the new access token
        let xboxToken = try await getXboxLiveTokenThrowing(accessToken: refreshedTokens.accessToken)
        let minecraftToken = try await getMinecraftTokenThrowing(xboxToken: xboxToken.token, uhs: xboxToken.displayClaims.xui.first?.uhs ?? "")

        // Create updated player object
        var updatedProfile = player.profile
        updatedProfile.lastPlayed = player.lastPlayed
        updatedProfile.isCurrent = player.isCurrent

        var updatedCredential = player.credential
        if var credential = updatedCredential {
            credential.accessToken = minecraftToken
            credential.refreshToken = refreshedTokens.refreshToken ?? player.authRefreshToken
            credential.xuid = xboxToken.displayClaims.xui.first?.uhs ?? player.authXuid
            updatedCredential = credential
        } else {
            // If there is no credential, create a new one
            updatedCredential = AuthCredential(
                userId: player.id,
                accessToken: minecraftToken,
                refreshToken: refreshedTokens.refreshToken ?? "",
                expiresAt: nil,
                xuid: xboxToken.displayClaims.xui.first?.uhs ?? ""
            )
        }

        let updatedPlayer = Player(profile: updatedProfile, credential: updatedCredential)

        return updatedPlayer
    }

    /// Refresh access token using refresh token (throws exception version)
    /// - Parameter refreshToken: refresh token
    /// - Returns: new token response
    /// - Throws: GlobalError when refresh fails
    private func refreshTokenThrowing(refreshToken: String) async throws -> TokenResponse {
        let url = URLConfig.API.Authentication.token

        // refresh_token may contain special characters and must be x-www-form-urlencoded encoded
        let bodyParameters: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken,
            "scope": scope,
        ]
        let bodyString = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        let bodyData = bodyString.data(using: .utf8)

        // Use unified API client (needs to handle non-200 status codes)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        // Check for OAuth errors
        if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = errorResponse["error"] as? String {
            switch error {
            case "invalid_grant":
                Logger.shared.error("刷新令牌已过期或无效")
                throw GlobalError.authentication(
                    i18nKey: "Refresh token is expired or invalid",
                    level: .notification
                )
            default:
                Logger.shared.error("刷新令牌错误: \(error)")
                throw GlobalError.authentication(
                    i18nKey: "Refresh token error",
                    level: .notification
                )
            }
        }

        guard httpResponse.statusCode == 200 else {
            Logger.shared.error("刷新访问令牌失败: HTTP \(httpResponse.statusCode)")
            throw GlobalError.download(
                i18nKey: "Refresh token request failed",
                level: .notification
            )
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// Check whether the Token has expired based on the timestamp
    /// - Parameter player: player object
    /// - Returns: Whether it has expired
    func isTokenExpiredBasedOnTime(for player: Player) async -> Bool {
        // Normal logic: Determine whether it is about to expire based on the exp field in the JWT (including 5-minute buffer)
        return JWTDecoder.isTokenExpiringSoon(player.authAccessToken)
    }

    /// Prompts the user to re-login to the specified player
    /// - Parameter player: Player who needs to log in again
    func promptForReauth(player: Player) {
        // Display notification prompting user to log in again
        let notification = GlobalError.authentication(
            i18nKey: "Login has expired, please re-login to this account in player management before starting the game",
            level: .notification
        )

        GlobalErrorHandler.shared.handle(notification)
    }
}

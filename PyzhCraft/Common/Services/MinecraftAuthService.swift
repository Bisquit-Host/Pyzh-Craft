import SwiftUI
import AuthenticationServices

class MinecraftAuthService: NSObject, ObservableObject {
    static let shared = MinecraftAuthService()

    @Published var authState: AuthenticationState = .notAuthenticated
    @Published var isLoading: Bool = false
    private var webAuthSession: ASWebAuthenticationSession?

    private let clientId = AppConstants.minecraftClientId
    private let scope = AppConstants.minecraftScope
    private let redirectUri = URLConfig.API.Authentication.redirectUri

    override private init() {
        super.init()
    }

    // MARK: - Authentication process (using ASWebAuthenticationSession)
    @MainActor
    func startAuthentication() async {
        // Clean up the previous state before starting a new authentication
        webAuthSession?.cancel()
        webAuthSession = nil

        isLoading = true
        authState = .waitingForBrowserAuth

        guard let authURL = buildAuthorizationURL() else {
            isLoading = false
            authState = .error(String(localized: "Authentication failed"))
            return
        }

        await withCheckedContinuation { continuation in
            webAuthSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: AppConstants.callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    if let error {
                        if let authError = error as? ASWebAuthenticationSessionError {
                            if authError.code == .canceledLogin {
                                Logger.shared.info("用户取消了 Microsoft 认证")
                                self?.authState = .notAuthenticated
                            } else {
                                                        Logger.shared.error("Microsoft 认证失败: \(authError.localizedDescription)")
                        self?.authState = .error(String(localized: "Authentication failed"))
                            }
                        } else {
                                                    Logger.shared.error("Microsoft 认证发生未知错误: \(error.localizedDescription)")
                        self?.authState = .error(String(localized: "Authentication failed"))
                        }
                        self?.isLoading = false
                        continuation.resume()
                        return
                    }

                    guard let callbackURL = callbackURL,
                          let authResponse = AuthorizationCodeResponse(from: callbackURL) else {
                        Logger.shared.error("Microsoft 无效的回调 URL")
                        self?.authState = .error(String(localized: "Invalid callback URL"))
                        self?.isLoading = false
                        continuation.resume()
                        return
                    }

                    // Check whether the user refused authorization
                    if authResponse.isUserDenied {
                        Logger.shared.info("用户拒绝了 Microsoft 授权")
                        self?.authState = .notAuthenticated
                        self?.isLoading = false
                        continuation.resume()
                        return
                    }

                    // Check for other errors
                    if let error = authResponse.error {
                        let description = authResponse.errorDescription ?? error
                        Logger.shared.error("Microsoft 授权失败: \(description)")
                        self?.authState = .error("授权失败: \(description)")
                        self?.isLoading = false
                        continuation.resume()
                        return
                    }

                    // Check whether the authorization code was successfully obtained
                    guard authResponse.isSuccess, let code = authResponse.code else {
                        Logger.shared.error("未获取到授权码")
                        self?.authState = .error(String(localized: "No authorization code received"))
                        self?.isLoading = false
                        continuation.resume()
                        return
                    }

                    await self?.handleAuthorizationCode(code)
                    continuation.resume()
                }
            }

            webAuthSession?.presentationContextProvider = self
            webAuthSession?.prefersEphemeralWebBrowserSession = false
            webAuthSession?.start()
        }
    }

    // MARK: - Construct the authorization URL (return nil in case of failure, handled by the caller to avoid crashing in the production environment)
    private func buildAuthorizationURL() -> URL? {
        guard var components = URLComponents(url: URLConfig.API.Authentication.authorize, resolvingAgainstBaseURL: false) else {
            Logger.shared.error("Invalid authorization URL configuration")
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]
        guard let url = components.url else {
            Logger.shared.error("Failed to build authorization URL")
            return nil
        }
        return url
    }

    // MARK: - Process authorization code
    @MainActor
    private func handleAuthorizationCode(_ code: String) async {
        authState = .processingAuthCode

        do {
            // Get access token using authorization code
            let tokenResponse = try await exchangeCodeForToken(code: code)

            // Get the complete certification chain
            let xboxToken = try await getXboxLiveTokenThrowing(accessToken: tokenResponse.accessToken)
            let minecraftToken = try await getMinecraftTokenThrowing(xboxToken: xboxToken.token, uhs: xboxToken.displayClaims.xui.first?.uhs ?? "")
            try await checkMinecraftOwnership(accessToken: minecraftToken)

            // Use JWT parsing to get the true expiration time of Minecraft tokens
            let minecraftTokenExpiration = JWTDecoder.getMinecraftTokenExpiration(from: minecraftToken)
            Logger.shared.info("Minecraft token过期时间: \(minecraftTokenExpiration)")

            // Create a profile with the correct expiration time
            let profile = try await getMinecraftProfileThrowing(
                accessToken: minecraftToken,
                authXuid: xboxToken.displayClaims.xui.first?.uhs ?? "",
                refreshToken: tokenResponse.refreshToken ?? ""
            )

            Logger.shared.info("Minecraft 认证成功，用户: \(profile.name)")
            isLoading = false
            authState = .authenticated(profile: profile)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Minecraft 认证失败: \(globalError.chineseMessage)")
            isLoading = false
            authState = .error(globalError.chineseMessage)
        }
    }

    // MARK: - exchange authorization code for access token
    private func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        let url = URLConfig.API.Authentication.token
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters = [
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code",
            "scope": scope,
        ]

        let bodyString = bodyParameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        let bodyData = bodyString.data(using: .utf8)

        // Use a unified API client
        let headers = ["Content-Type": "application/x-www-form-urlencoded"]
        let data = try await APIClient.post(url: url, body: bodyData, headers: headers)

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GlobalError.validation(
                i18nKey: "Token response parse failed",
                level: .notification
            )
        }
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(accessToken)",
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
        var xstsRequest = URLRequest(url: xstsUrl)
        xstsRequest.httpMethod = "POST"
        xstsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
            throw GlobalError(type: .validation, i18nKey: "XSTS Request Serialize Failed", level: .notification)
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
                    i18nKey: "Failed to check game ownership: HTTP %@",
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
                i18nKey: "Failed to parse game entitlements response: %@",
                level: .notification
            )
        } catch let globalError as GlobalError {
            // Rethrow GlobalError
            throw globalError
        } catch {
            throw GlobalError.validation(
                i18nKey: "Unknown error occurred while checking game ownership: %@",
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
        webAuthSession?.cancel()
        webAuthSession = nil
        isLoading = false
    }

    // MARK: - Clean authentication data
    @MainActor
    func clearAuthenticationData() {
        authState = .notAuthenticated
        isLoading = false
        webAuthSession?.cancel()
        webAuthSession = nil
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
                i18nKey: "Unknown error occurred while refreshing token: %@",
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

// MARK: - ASWebAuthenticationPresentationContextProviding
extension MinecraftAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return to the main window as the display anchor
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

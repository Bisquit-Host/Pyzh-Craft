import Foundation

enum PlayerSkinService {

    // MARK: - Notification System

    static let playerUpdatedNotification = Notification.Name("PlayerUpdated")

    private static func notifyPlayerUpdated(_ updatedPlayer: Player) {
        NotificationCenter.default.post(
            name: playerUpdatedNotification,
            object: nil,
            userInfo: ["updatedPlayer": updatedPlayer]
        )
    }

    // MARK: - Error Handling
    private static func handleError(_ error: Error, operation: String) {
        let globalError = GlobalError.from(error)
        Logger.shared.error("\(operation) failed: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
    }

    // MARK: - Common Error Helpers
    private static func validateAccessToken(_ player: Player) throws {
        guard !player.authAccessToken.isEmpty else {
            throw GlobalError.authentication(i18nKey: "Access token is missing, please log in again",
                level: .popup
            )
        }
    }

    private static func handleHTTPError(_ http: HTTPURLResponse, operation: String) throws {
        switch http.statusCode {
        case 400:
            throw GlobalError.validation(i18nKey: "Invalid request parameters",
                level: .notification
            )
        case 401:
            throw GlobalError.authentication(i18nKey: "Access token has expired, please log in again",
                level: .popup
            )
        case 403:
            throw GlobalError(type: .authentication, i18nKey: "\(operation) forbidden",
                level: .notification
            )
        case 404:
            throw GlobalError.resource(i18nKey: "The requested resource was not found",
                level: .notification
            )
        case 429:
            throw GlobalError.network(i18nKey: "Too many requests, please try again later",
                level: .notification
            )
        default:
            throw GlobalError(type: .network, i18nKey: "\(operation) HTTP error",
                level: .notification
            )
        }
    }

    struct PublicSkinInfo: Codable, Equatable {
        let skinURL: String?
        let model: SkinModel
        let capeURL: String?
        let fetchedAt: Date

        enum SkinModel: String, Codable, CaseIterable { case classic, slim }
    }

    /// Update player skin information to data manager
    /// - Parameters:
    ///   - uuid: player UUID
    ///   - skinInfo: skin information
    /// - Returns: Whether the update is successful
    private static func updatePlayerSkinInfo(uuid: String, skinInfo: PublicSkinInfo) async -> Bool {
        do {
            let dataManager = PlayerDataManager()
            let players = try dataManager.loadPlayersThrowing()

            guard let player = players.first(where: { $0.id == uuid }) else {
                Logger.shared.warning("Player not found for UUID: \(uuid)")
                return false
            }

            // Create updated player object
            let updatedProfile = UserProfile(
                id: player.profile.id,
                name: player.profile.name,
                avatar: skinInfo.skinURL?.httpToHttps() ?? player.avatarName,
                lastPlayed: player.lastPlayed,
                isCurrent: player.isCurrent
            )

            let updatedCredential = player.credential

            let updatedPlayer = Player(profile: updatedProfile, credential: updatedCredential)

            // Update data using dataManager
            try dataManager.updatePlayer(updatedPlayer)

            // Notify ViewModel to update the current player
            notifyPlayerUpdated(updatedPlayer)

            return true
        } catch {
            Logger.shared.error("Failed to update player skin info: \(error.localizedDescription)")
            return false
        }
    }

    /// Get the current player's skin information using the Minecraft Services API (more accurate, no caching delays)
    /// - Parameter player: player information
    /// - Returns: Skin information, if the acquisition fails, return nil
    static func fetchCurrentPlayerSkinFromServices(player: Player) async -> PublicSkinInfo? {
        do {
            let profile = try await fetchPlayerProfileThrowing(player: player)

            // Extract skin information from Minecraft Services API response
            guard !profile.skins.isEmpty else {
                Logger.shared.warning("玩家没有皮肤信息")
                return nil
            }

            // Find the currently active skin
            let activeSkin = profile.skins.first { $0.state == "ACTIVE" } ?? profile.skins.first

            guard let skin = activeSkin else {
                Logger.shared.warning("没有找到激活的皮肤")
                return nil
            }

            let skinInfo = PublicSkinInfo(
                skinURL: skin.url,
                model: skin.variant == "SLIM" ? .slim : .classic,
                capeURL: nil, // The Minecraft Services API does not provide cloak information directly
                fetchedAt: Date()
            )

            return skinInfo
        } catch {
            Logger.shared.error("从 Minecraft Services API 获取皮肤信息失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Upload Skin (multipart/form-data)
    /// Upload (silent version)
    /// - Parameters:
    ///   - imageData: PNG image data (64x64 or 64x32 standard formats)
    ///   - model: Skin model classic / slim
    ///   - player: Current online player (requires valid accessToken)
    /// - Returns: Whether successful
    static func uploadSkin(
        imageData: Data,
        model: PublicSkinInfo.SkinModel,
        player: Player
    ) async -> Bool {
        do {
            try await uploadSkinThrowing(
                imageData: imageData,
                model: model,
                player: player
            )
            return true
        } catch {
            handleError(error, operation: "Upload skin")
            return false
        }
    }

    /// Refresh skin information (public method)
    /// - Parameter player: player information
    private static func refreshSkinInfo(player: Player) async {
        if let newSkinInfo = await fetchCurrentPlayerSkinFromServices(player: player) {
            _ = await updatePlayerSkinInfo(uuid: player.id, skinInfo: newSkinInfo)
        }
    }

    /// Handle the complete process after skin upload (including data updates and notifications)
    /// - Parameters:
    ///   - imageData: skin image data
    ///   - model: skin model
    ///   - player: player information
    /// - Returns: Success or not
    static func uploadSkinAndRefresh(
        imageData: Data,
        model: PublicSkinInfo.SkinModel,
        player: Player
    ) async -> Bool {
        let success = await uploadSkin(imageData: imageData, model: model, player: player)
        if success {
            await refreshSkinInfo(player: player)
        }
        return success
    }

    /// Reset skin and refresh data
    /// - Parameter player: player information
    /// - Returns: Success or not
    static func resetSkinAndRefresh(player: Player) async -> Bool {
        let success = await resetSkin(player: player)
        if success {
            await refreshSkinInfo(player: player)
        }
        return success
    }

    /// Upload (throwing version)
    /// Implemented according to https://zh.minecraft.wiki/w/Mojang_API#upload-skin specification
    static func uploadSkinThrowing(
        imageData: Data,
        model: PublicSkinInfo.SkinModel,
        player: Player
    ) async throws {
        try validateAccessToken(player)

        // Use string interpolation instead of string concatenation
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func appendField(name: String, value: String) {
            if let fieldData =
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
                .data(using: .utf8) {
                body.append(fieldData)
            }
        }
        func appendFile(
            name: String,
            filename: String,
            mime: String,
            data: Data
        ) {
            var part = Data()
            func appendString(_ s: String) {
                if let d = s.data(using: .utf8) { part.append(d) }
            }
            appendString("--\(boundary)\r\n")
            appendString(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
            )
            appendString("Content-Type: \(mime)\r\n\r\n")
            part.append(data)
            appendString("\r\n")
            body.append(part)
        }
        let variantValue = model == .slim ? "SLIM" : "CLASSIC"
        Logger.shared.info("Uploading skin with variant: \(variantValue), data size: \(imageData.count) bytes")

        appendField(name: "variant", value: variantValue)
        appendFile(
            name: "file",
            filename: "skin.png",
            mime: "image/png",
            data: imageData
        )
        if let closing = "--\(boundary)--\r\n".data(using: .utf8) {
            body.append(closing)
        }

        var request = URLRequest(
            url: URLConfig.API.Authentication.minecraftProfileSkins
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(player.authAccessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        request.timeoutInterval = 30

        // Use unified API client (needs to handle non-200 status codes)
        let (_, http) = try await APIClient.performRequestWithResponse(request: request)
        switch http.statusCode {
        case 200, 204:
            Logger.shared.info("Skin upload successful with variant: \(variantValue)")
            return
        case 400:
            Logger.shared.error("Skin upload failed with 400: Invalid skin file or variant")
            throw GlobalError.validation(i18nKey: "Invalid skin file",
                level: .popup
            )
        default:
            Logger.shared.error("Skin upload failed with HTTP \(http.statusCode)")
            try handleHTTPError(http, operation: "皮肤上传")
        }
    }

    // MARK: - Reset Skin (delete active)
    static func resetSkin(player: Player) async -> Bool {
        do {
            try await resetSkinThrowing(player: player)
            return true
        } catch {
            handleError(error, operation: "Reset skin")
            return false
        }
    }

    // MARK: - Common Helper Methods

    /// Get the currently active cloak ID
    /// - Parameter profile: player profile
    /// - Returns: ID of the activated cloak, or nil if there is none
    static func getActiveCapeId(from profile: MinecraftProfileResponse?) -> String? {
        return profile?.capes?.first { $0.state == "ACTIVE" }?.id
    }

    /// Check for skin changes
    /// - Parameters:
    ///   - selectedSkinData: selected skin data
    ///   - currentModel: current model
    ///   - originalModel: original model (optional, nil means there is no existing skin)
    /// - Returns: Whether there are skin changes
    static func hasSkinChanges(
        selectedSkinData: Data?,
        currentModel: PublicSkinInfo.SkinModel,
        originalModel: PublicSkinInfo.SkinModel?
    ) -> Bool {
        // If there is selected skin data, there are changes
        if selectedSkinData != nil {
            return true
        }

        // If there is no original model information (no existing skin), but the current model is not the default classic, there are changes
        if originalModel == nil && currentModel != .classic {
            return true
        }

        // If original model information is available, compare the current model with the original model
        if let original = originalModel {
            return currentModel != original
        }

        return false
    }

    /// Check for cape changes
    /// - Parameters:
    ///   - selectedCapeId: selected cape ID
    ///   - currentActiveCapeId: currently active cape ID
    /// - Returns: Whether there are cape changes
    static func hasCapeChanges(selectedCapeId: String?, currentActiveCapeId: String?) -> Bool {
        selectedCapeId != currentActiveCapeId
    }

    // MARK: - Cape Management
    /// Get player profile with capes information (silent version)
    /// - Parameter player: Current online player
    /// - Returns: Profile with cape information or nil if failed
    static func fetchPlayerProfile(player: Player) async
        -> MinecraftProfileResponse? {
        do {
            return try await fetchPlayerProfileThrowing(player: player)
        } catch {
            handleError(error, operation: "Fetch player profile")
            return nil
        }
    }

    /// Get player profile with capes information (throwing version)
    static func fetchPlayerProfileThrowing(player: Player) async throws
        -> MinecraftProfileResponse {
        try validateAccessToken(player)

        var request = URLRequest(
            url: URLConfig.API.Authentication.minecraftProfile
        )
        request.setValue(
            "Bearer \(player.authAccessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 30

        // Use unified API client (needs to handle non-200 status codes)
        let (data, http) = try await APIClient.performRequestWithResponse(request: request)
        switch http.statusCode {
        case 200:
            break
        default:
            try handleHTTPError(http, operation: "获取个人资料")
        }

        let profile = try JSONDecoder().decode(
            MinecraftProfileResponse.self,
            from: data
        )
        return MinecraftProfileResponse(
            id: profile.id,
            name: profile.name,
            skins: profile.skins,
            capes: profile.capes,
            accessToken: player.authAccessToken,
            authXuid: player.authXuid,
            refreshToken: player.authRefreshToken
        )
    }

    /// Show/equip a cape (silent version)
    /// - Parameters:
    ///   - capeId: Cape UUID to equip
    ///   - player: Current online player
    /// - Returns: Whether successful
    static func showCape(capeId: String, player: Player) async -> Bool {
        do {
            try await showCapeThrowing(capeId: capeId, player: player)
            return true
        } catch {
            handleError(error, operation: "Show cape")
            return false
        }
    }

    /// Show/equip a cape (throwing version)
    /// Implemented according to https://zh.minecraft.wiki/w/Mojang_API#show-cape specification
    static func showCapeThrowing(capeId: String, player: Player) async throws {
        try validateAccessToken(player)

        let payload = ["capeId": capeId]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(
            url: URLConfig.API.Authentication.minecraftProfileActiveCape
        )
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(player.authAccessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        // Use unified API client (needs to handle non-200 status codes)
        let (_, http) = try await APIClient.performRequestWithResponse(request: request)
        switch http.statusCode {
        case 200, 204:
            return
        case 400:
            throw GlobalError.validation(i18nKey: "Invalid cape ID or request",
                level: .notification
            )
        case 401:
            throw GlobalError.authentication(i18nKey: "Access token is invalid or expired, please log in again",
                level: .popup
            )
        case 403:
            throw GlobalError.authentication(i18nKey: "No permission to equip cape (403)",
                level: .notification
            )
        case 404:
            throw GlobalError.resource(i18nKey: "Cape not found or not owned",
                level: .notification
            )
        default:
            throw GlobalError.network(i18nKey: "Show cape failed: HTTP %@",
                level: .notification
            )
        }
    }

    /// Hide current cape (silent version)
    /// - Parameter player: Current online player
    /// - Returns: Whether successful
    static func hideCape(player: Player) async -> Bool {
        do {
            try await hideCapeThrowing(player: player)
            return true
        } catch {
            handleError(error, operation: "Hide cape")
            return false
        }
    }

    /// Hide current cape (throwing version)
    /// Implemented according to https://zh.minecraft.wiki/w/Mojang_API#hide-cape specification
    static func hideCapeThrowing(player: Player) async throws {
        try validateAccessToken(player)

        var request = URLRequest(
            url: URLConfig.API.Authentication.minecraftProfileActiveCape
        )
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer \(player.authAccessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 30

        // Use unified API client (needs to handle non-200 status codes)
        let (_, http) = try await APIClient.performRequestWithResponse(request: request)
        switch http.statusCode {
        case 200, 204:
            return
        case 401:
            throw GlobalError.authentication(i18nKey: "Access token is invalid or expired, please log in again",
                level: .popup
            )
        default:
            throw GlobalError.network(i18nKey: "Hide cape failed: HTTP %@",
                level: .notification
            )
        }
    }

    static func resetSkinThrowing(player: Player) async throws {
        try validateAccessToken(player)
        var request = URLRequest(
            url: URLConfig.API.Authentication.minecraftProfileActiveSkin
        )
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer \(player.authAccessToken)",
            forHTTPHeaderField: "Authorization"
        )
        // Use unified API client (needs to handle non-200 status codes)
        let (_, http) = try await APIClient.performRequestWithResponse(request: request)
        switch http.statusCode {
        case 200, 204:
            return
        case 401:
            throw GlobalError.authentication(i18nKey: "Access token is invalid or expired, please log in again",
                level: .popup
            )
        default:
            throw GlobalError.network(i18nKey: "Reset skin failed: HTTP %@",
                level: .notification
            )
        }
    }
}

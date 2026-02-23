import Foundation

// MARK: - Microsoft Device Code
struct MicrosoftDeviceCodeResponse: Codable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code",
             userCode = "user_code",
             verificationURI = "verification_uri",
             verificationURIComplete = "verification_uri_complete",
             expiresIn = "expires_in",
             interval,
             message
    }
    
    var displayVerificationURL: String {
        verificationURIComplete ?? verificationURI
    }
}

struct MicrosoftOAuthErrorResponse: Codable {
    let error: String
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Token Response
struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token",
             refreshToken = "refresh_token",
             expiresIn = "expires_in"
    }
}

// MARK: - Xbox Live Token Response
struct XboxLiveTokenResponse: Codable {
    let token: String
    let displayClaims: DisplayClaims
    
    enum CodingKeys: String, CodingKey {
        case token = "Token",
             displayClaims = "DisplayClaims"
    }
}

struct DisplayClaims: Codable {
    let xui: [XUI]
    
    enum CodingKeys: String, CodingKey {
        case xui
    }
}

struct XUI: Codable {
    let uhs: String
    
    enum CodingKeys: String, CodingKey {
        case uhs
    }
}

// MARK: - Minecraft Profile Response
struct MinecraftProfileResponse: Codable, Equatable {
    let id: String
    let name: String
    let skins: [Skin]
    let capes: [Cape]?
    let accessToken: String
    let authXuid: String
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, skins, capes
        // accessToken and authXuid are not involved in decoding because they are not obtained from the API response
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        skins = try container.decode([Skin].self, forKey: .skins)
        capes = try container.decodeIfPresent([Cape].self, forKey: .capes)
        // These fields will be set externally
        accessToken = ""
        authXuid = ""
        refreshToken = ""
    }
    
    init(id: String, name: String, skins: [Skin], capes: [Cape]?, accessToken: String, authXuid: String, refreshToken: String = "") {
        self.id = id
        self.name = name
        self.skins = skins
        self.capes = capes
        self.accessToken = accessToken
        self.authXuid = authXuid
        self.refreshToken = refreshToken
    }
}

struct Skin: Codable, Equatable {
    let state: String
    let url: String
    let variant: String?
}

struct Cape: Codable, Equatable {
    let id: String
    let state: String
    let url: String
    let alias: String?
}

// MARK: - Minecraft Entitlements Response
struct MinecraftEntitlementsResponse: Codable {
    let items: [EntitlementItem]
    let signature: String
    let keyId: String
}

struct EntitlementItem: Codable {
    let name: String
    let signature: String
}

// MARK: - Entitlement Names
enum MinecraftEntitlement: String, CaseIterable {
    case productMinecraft = "product_minecraft"
    case gameMinecraft = "game_minecraft"
    
    var displayName: String {
        switch self {
        case .productMinecraft: "Minecraft Product License"
        case .gameMinecraft: "Minecraft Game License"
        }
    }
}

// MARK: - Authentication State
enum AuthenticationState: Equatable {
    case notAuthenticated,
         waitingForBrowserAuth,          // Wait for the user to complete authorization in the browser
         processingAuthCode,             // Process authorization code
         authenticated(profile: MinecraftProfileResponse),
         error(String)
}

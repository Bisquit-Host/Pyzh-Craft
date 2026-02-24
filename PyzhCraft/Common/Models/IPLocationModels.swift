import Foundation

/// IP Geolocation Response Model (ipapi.co API format)
struct IPLocationResponse: Codable {
    let countryCode: String?
    let error: Bool
    let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case countryCode = "country_code",
             error, reason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        error = try container.decodeIfPresent(Bool.self, forKey: .error) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
    
    /// Whether the request was successful
    var isSuccess: Bool {
        !error && countryCode != nil
    }
    
    /// Is it a Chinese IP?
    var isChina: Bool {
        countryCode == "CN"
    }
    
    /// Is it a foreign IP?
    var isForeign: Bool {
        isSuccess && !isChina
    }
}

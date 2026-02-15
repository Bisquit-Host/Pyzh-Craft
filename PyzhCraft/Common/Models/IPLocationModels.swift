import Foundation

/// IP地理位置响应模型 (ipapi.co API格式)
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

    /// 是否请求成功
    var isSuccess: Bool {
        !error && countryCode != nil
    }

    /// 是否为中国IP
    var isChina: Bool {
        countryCode == "CN"
    }

    /// 是否为国外IP
    var isForeign: Bool {
        isSuccess && !isChina
    }
}

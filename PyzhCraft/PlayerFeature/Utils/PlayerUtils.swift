import CryptoKit
import SwiftUI

/// Player Tools
enum PlayerUtils {
    // MARK: - Constants

    private static let names = ["alex", "ari", "efe", "kai", "makena", "noor", "steve", "sunny", "zuri"]
    private static let offlinePrefix = "OfflinePlayer:"

    // MARK: - UUID Generation

    static func generateOfflineUUID(for username: String) throws -> String {
        guard !username.isEmpty else {
            throw GlobalError.player(
                i18nKey: "Invalid Username Empty",
                level: .notification
            )
        }

        guard let data = (offlinePrefix + username).data(using: .utf8) else {
            throw GlobalError.validation(
                i18nKey: "Username Encode Failed",
                level: .notification
            )
        }

        var bytes = [UInt8](Insecure.MD5.hash(data: data))
        bytes[6] = (bytes[6] & 0x0F) | 0x30 // Version 3
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122
        let uuid = bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
        let uuidString = uuid.uuidString.lowercased()
        Logger.shared.debug("Generate offline UUID - Username: \(username), UUID: \(uuidString)")
        return uuidString
    }

    // MARK: - Avatar Name Generation

    static func avatarName(for uuid: String) -> String? {
        guard let index = nameIndex(for: uuid) else {
            Logger.shared.warning("Unable to get avatar name - invalid UUID: \(uuid)")
            return nil
        }
        return names[index]
    }

    private static func nameIndex(for uuid: String) -> Int? {
        let cleanUUID = uuid.replacingOccurrences(of: "-", with: "")
        guard cleanUUID.count >= 32 else { return nil }
        let iStr = String(cleanUUID.prefix(16))
        let uStr = String(cleanUUID.dropFirst(16).prefix(16))
        guard let i = UInt64(iStr, radix: 16), let u = UInt64(uStr, radix: 16) else { return nil }
        let f = i ^ u
        let mixedBits = (f ^ (f >> 32)) & 0xffff_ffff
        let ii = Int32(bitPattern: UInt32(truncatingIfNeeded: mixedBits))
        return (Int(ii) % names.count + names.count) % names.count
    }
}

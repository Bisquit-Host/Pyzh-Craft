import Foundation

/// Unified decryption tool
/// Supports decryption of Client ID and API Key
enum Obfuscator {
    private static let xorKey: UInt8 = 0x7A
    private static let indexOrder = [3, 0, 5, 1, 4, 2]

    // MARK: - Decrypt core method

    private static func decrypt(_ input: String) -> String {
        guard let data = Data(base64Encoded: input) else { return "" }
        let bytes = data.map { ($0 ^ xorKey) >> 3 | ($0 ^ xorKey) << 5 }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func chunked(_ string: String, length: Int) -> [String] {
        guard length > 0 else { return [] }

        var chunks: [String] = []
        var startIndex = string.startIndex

        while startIndex < string.endIndex {
            let endIndex = string.index(
                startIndex,
                offsetBy: length,
                limitedBy: string.endIndex
            ) ?? string.endIndex
            chunks.append(String(string[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }

    // MARK: - Client ID method

    /// Decrypt Client ID
    static func decryptClientID(_ encryptedString: String) -> String {
        // Split the encrypted string into fixed lengths (8 characters per part)
        let partLength = 8
        var parts = chunked(encryptedString, length: partLength)
        if parts.count < indexOrder.count {
            parts.append(contentsOf: repeatElement("", count: indexOrder.count - parts.count))
        } else if parts.count > indexOrder.count {
            parts = Array(parts.prefix(indexOrder.count))
        }

        // Restore original order according to indexOrder
        var restoredParts = Array(repeating: "", count: parts.count)
        for (j, part) in parts.enumerated() {
            if let i = indexOrder.firstIndex(of: j) {
                restoredParts[i] = decrypt(part)
            }
        }

        return restoredParts.joined()
    }

    // MARK: - API Key method

    /// Decrypt API Key
    static func decryptAPIKey(_ encryptedString: String) -> String {
        // Calculate the number of parts that need to be split (each part is 8 characters after encryption)
        let partLength = 8

        // Split encrypted string by fixed length
        var parts = chunked(encryptedString, length: partLength)

        // If the number of parts is less than 6, it needs to be filled to 6
        while parts.count < 6 {
            parts.append("")
        }

        // Restore original order by indexOrder (only first 6 parts are processed)
        var restoredParts = Array(repeating: "", count: min(parts.count, 6))
        for (j, part) in parts.prefix(6).enumerated() {
            if j < indexOrder.count, let i = indexOrder.firstIndex(of: j) {
                if i < restoredParts.count {
                    restoredParts[i] = decrypt(part)
                }
            }
        }

        // If there are more than 6 parts, decrypt directly in sequence
        var result = restoredParts.joined()
        if parts.count > 6 {
            for part in parts.suffix(from: 6) {
                result += decrypt(part)
            }
        }

        return result
    }
}

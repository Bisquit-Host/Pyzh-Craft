import Foundation
import CommonCrypto
import CryptoKit

/// Unified SHA1 calculation tool class
public enum SHA1Calculator {

    /// Computes the SHA1 hash of Data (good for small files or in-memory data)
    /// - Parameter data: The data to calculate the hash
    /// - Returns: SHA1 hash string
    public static func sha1(of data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Calculate the SHA1 hash of a file (streaming, for large files)
    /// - Parameter url: file path
    /// - Returns: SHA1 hash string
    /// - Throws: GlobalError when the operation fails
    public static func sha1(ofFileAt url: URL) throws -> String {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            var context = CC_SHA1_CTX()
            CC_SHA1_Init(&context)

            // Use 1MB buffer for streaming
            let bufferSize = 1024 * 1024

            while autoreleasepool(invoking: {
                let data = fileHandle.readData(ofLength: bufferSize)
                if !data.isEmpty {
                    data.withUnsafeBytes { bytes in
                        _ = CC_SHA1_Update(&context, bytes.baseAddress, CC_LONG(data.count))
                    }
                    return true
                }
                return false
            }) {}

            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            _ = CC_SHA1_Final(&digest, &context)

            return digest.map { String(format: "%02hhx", $0) }.joined()
        } catch {
            throw GlobalError.fileSystem(i18nKey: "SHA1 Calculation Failed",
                level: .notification
            )
        }
    }

    /// Compute SHA1 hash of file (silent version, returns optional value)
    /// - Parameter url: file path
    /// - Returns: SHA1 hash string, or nil if the calculation fails
    public static func sha1Silent(ofFileAt url: URL) -> String? {
        do {
            return try sha1(ofFileAt: url)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("计算文件哈希值失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Calculate SHA1 using CryptoKit (for scenarios requiring CryptoKit features)
    /// - Parameter data: The data to calculate the hash
    /// - Returns: SHA1 hash string
    public static func sha1WithCryptoKit(of data: Data) -> String {
        let hash = Insecure.SHA1.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Data Extension (maintains backward compatibility)
extension Data {
    /// Calculate the SHA1 hash value of the current Data
    var sha1: String {
        SHA1Calculator.sha1(of: self)
    }
}

import Foundation
import Network

/// Server connection status
enum ServerConnectionStatus {
    case unknown, checking,
         success(serverInfo: MinecraftServerInfo?),
         timeout, failed
}

/// Parsed server address information
struct ResolvedServerAddress {
    let address: String  // The address of the actual connection (SRV target or original address)
    let port: Int        // The actual connected port (SRV port or raw port)
    let originalAddress: String  // Original domain name (used for handshake)
    let originalPort: Int        // Raw port (used for handshake)
}

/// Network tools
/// Provides functions such as network connection detection
enum NetworkUtils {
    /// Intelligent resolution of server address
    /// Automatically determine the port based on user input. If there is no port, query the SRV record
    /// - Parameter input: The address entered by the user (may include a port, such as "example.com:25565" or "example.com")
    /// - Returns: parsed address and port (including original address information)
    static func resolveServerAddress(_ input: String) async -> ResolvedServerAddress {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        var originalAddress = trimmed
        var originalPort = 25565
        
        // Check if the port is included
        if let colonIndex = trimmed.lastIndex(of: ":") {
            // Check whether the content after the colon is a number (port)
            let afterColon = String(trimmed[trimmed.index(after: colonIndex)...])
            if let port = Int(afterColon), port > 0 && port <= 65535 {
                // Contains valid ports, use them directly
                let address = String(trimmed[..<colonIndex])
                originalAddress = address
                originalPort = port
                return ResolvedServerAddress(
                    address: address,
                    port: port,
                    originalAddress: originalAddress,
                    originalPort: originalPort
                )
            }
        }
        
        // Does not contain port, query SRV record
        if let srvResult = await querySRVRecord(for: trimmed) {
            // The SRV record returns the connection address, and the original address is the entered domain name
            return ResolvedServerAddress(
                address: srvResult.address,
                port: srvResult.port,
                originalAddress: trimmed,
                originalPort: 25565  // Default port
            )
        }
        
        // No SRV records, default port 25565 is used
        return ResolvedServerAddress(
            address: trimmed,
            port: 25565,
            originalAddress: trimmed,
            originalPort: 25565
        )
    }
    
    /// Query Minecraft SRV records
    /// - Parameter domain: domain name
    /// - Returns: Address and port in the SRV record (only connection information), or nil if none
    private static func querySRVRecord(for domain: String) async -> (address: String, port: Int)? {
        let srvName = "_minecraft._tcp.\(domain)"
        
        // Use the system's dig command to query SRV records (easier and more reliable)
        guard let output = await runDigShortSRVQuery(srvName: srvName) else { return nil }
        
        // Parse SRV record format: priority weight port target
        // For example: "5 0 25565 mc.example.com."
        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        guard let firstLine = lines.first, !firstLine.isEmpty else {
            return nil
        }
        
        let components = firstLine.split(separator: " ").map(String.init)
        guard components.count >= 4 else {
            return nil
        }
        
        guard let port = Int(components[2]), port > 0 && port <= 65535 else {
            return nil
        }
        
        var target = components[3]
        // Remove the trailing dot (if any)
        if target.hasSuffix(".") {
            target = String(target.dropLast())
        }
        
        return (address: target, port: port)
    }
    
    /// Asynchronously execute `dig +short SRV <srvName>` and return stdout text
    private static func runDigShortSRVQuery(srvName: String) async -> String? {
        await withCheckedContinuation { continuation in
            final class ResumeGuard: @unchecked Sendable {
                private let lock = NSLock()
                private var didResume = false
                private let continuation: CheckedContinuation<String?, Never>
                
                init(continuation: CheckedContinuation<String?, Never>) {
                    self.continuation = continuation
                }
                
                func resumeOnce(_ value: String?) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: value)
                }
            }
            let resumeGuard = ResumeGuard(continuation: continuation)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
            process.arguments = ["+short", "SRV", srvName]
            
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()
            
            process.terminationHandler = { proc in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                try? stdoutPipe.fileHandleForReading.close()
                
                guard proc.terminationStatus == 0 else {
                    Logger.shared.debug("dig query failed, exit status: \(proc.terminationStatus)")
                    resumeGuard.resumeOnce(nil)
                    return
                }
                
                guard let output = String(data: data, encoding: .utf8) else {
                    resumeGuard.resumeOnce(nil)
                    return
                }
                
                resumeGuard.resumeOnce(output)
            }
            
            do {
                try process.run()
            } catch {
                Logger.shared.debug("Unable to start dig process: \(error.localizedDescription)")
                resumeGuard.resumeOnce(nil)
            }
        }
    }
    /// Check server connection status (using Minecraft Server List Ping protocol)
    /// - Parameters:
    ///   - address: server address
    ///   - port: server port
    ///   - timeout: timeout (seconds), default 5 seconds
    /// - Returns: connection status, including server information when successful
    static func checkServerConnectionStatus(
        address: String,
        port: Int,
        timeout: TimeInterval = 5.0
    ) async -> ServerConnectionStatus {
        // Resolve server address (query SRV record)
        let resolved = await resolveServerAddress(address)
        
        // Get server information using the Minecraft Server List Ping protocol
        // Use SRV target + port to establish connection, but handshake uses original domain name
        if let serverInfo = await MinecraftServerPing.ping(
            connectAddress: resolved.address,
            connectPort: resolved.port,
            originalAddress: resolved.originalAddress,
            originalPort: resolved.originalPort,
            timeout: timeout
        ) {
            return .success(serverInfo: serverInfo)
        } else {
            return .timeout
        }
    }
    
    /// Detect whether the server connection is available (compatible with old interfaces)
    /// - Parameters:
    ///   - address: server address
    ///   - port: server port
    ///   - timeout: timeout (seconds), default 5 seconds
    /// - Returns: detection result, true means the connection is successful, false means the connection failed
    /// - Throws: Errors in the detection process
    static func checkServerConnection(
        address: String,
        port: Int,
        timeout: TimeInterval = 5.0
    ) async throws -> Bool {
        let status = await checkServerConnectionStatus(address: address, port: port, timeout: timeout)
        if case .success = status {
            return true
        }
        return false
    }
}

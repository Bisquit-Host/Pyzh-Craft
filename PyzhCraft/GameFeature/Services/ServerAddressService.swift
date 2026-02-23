import Foundation
import CryptoKit

/// Server address service
/// Responsible for reading and managing the server address list of the Minecraft game
@MainActor
class ServerAddressService {
    static let shared = ServerAddressService()

    private init() {}

    /// Read a list of server addresses from the game directory (only reads from servers.dat)
    /// - Parameter gameName: game name
    /// - Returns: Server address list
    func loadServerAddresses(for gameName: String) async throws -> [ServerAddress] {
        let profileDir = AppPaths.profileDirectory(gameName: gameName)
        let serversDatURL = profileDir.appendingPathComponent("servers.dat")

        guard FileManager.default.fileExists(atPath: serversDatURL.path) else {
            Logger.shared.debug("servers.dat file does not exist: \(serversDatURL.path)")
            return []
        }
        Logger.shared.debug("Start reading servers.dat: \(serversDatURL.path)")
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: serversDatURL)
            }.value
            Logger.shared.debug("servers.dat file size: \(data.count) bytes")
            let servers = try parseServersDat(data: data)
            Logger.shared.debug("Successfully resolved \(servers.count) servers")
            return servers
        } catch {
            Logger.shared.warning("Failed to parse server address servers.dat file: \(error.localizedDescription)")
            // Return an empty array when parsing fails instead of throwing an error
            return []
        }
    }

    /// Parse servers.dat file (NBT format)
    /// - Parameter data: file data
    /// - Returns: Server address list
    /// - Throws: Parsing errors
    private func parseServersDat(data: Data) throws -> [ServerAddress] {
        let parser = NBTParser(data: data)
        let nbtData = try parser.parse()

        Logger.shared.debug("NBT parsing completed, root tag key: \(nbtData.keys.joined(separator: ", "))")

        // servers.dat structure:
        // TAG_Compound("")
        //   TAG_List("servers")
        //     TAG_Compound
        //       TAG_String("name") - server name
        //       TAG_String("ip") - server address (may include port, format "ip:port")
        //       TAG_Byte("hidden") - whether to hide (optional, 0 or 1)
        //       TAG_String("icon") - Server icon (optional, Base64 encoded)
        //       TAG_Byte("acceptTextures") - whether to accept textures (optional, 0 or 1)

        guard let serversList = nbtData["servers"] as? [[String: Any]] else {
            Logger.shared.debug("Server list not found, or type does not match")
            // If there is no servers list, an empty array is returned
            return []
        }

        Logger.shared.debug("Found \(serversList.count) server entries")

        var servers: [ServerAddress] = []

        for serverData in serversList {
            guard let name = serverData["name"] as? String,
                  let ip = serverData["ip"] as? String else {
                // Skip servers missing required fields
                continue
            }

            // Resolve IP addresses and ports
            let (address, port) = parseIPAndPort(ip)

            // Read optional fields
            // NBT Byte type may be Int8 or other integer type after parsing
            let hidden: Bool
            if let hiddenValue = serverData["hidden"] as? Int8 {
                hidden = hiddenValue != 0
            } else if let hiddenValue = serverData["hidden"] as? Int {
                hidden = hiddenValue != 0
            } else {
                hidden = false
            }

            let icon = serverData["icon"] as? String

            let acceptTextures: Bool
            // Read preventsChatReports (official field)
            if let preventsValue = serverData["preventsChatReports"] as? Int8 {
                acceptTextures = preventsValue != 0
            } else if let preventsValue = serverData["preventsChatReports"] as? Int {
                acceptTextures = preventsValue != 0
            } else {
                acceptTextures = false
            }

            // Use a hash of the server content to generate a stable ID, ensuring that the ID remains consistent after rereading
            let stableId = generateStableServerId(name: name, address: address, port: port)

            let server = ServerAddress(
                id: stableId,
                name: name,
                address: address,
                port: port,
                hidden: hidden,
                icon: icon,
                acceptTextures: acceptTextures
            )

            servers.append(server)
        }

        return servers
    }

    /// Resolve IP addresses and ports
    /// - Parameter ipString: IP string, in the format of "ip" or "ip:port"
    /// - Returns: (address, port) tuple, port 0 means not set
    private func parseIPAndPort(_ ipString: String) -> (String, Int) {
        let components = ipString.split(separator: ":")

        if components.count == 2,
           let port = Int(components[1]),
           port > 0 {
            return (String(components[0]), port)
        }

        // If there is no port or the port is invalid, return 0 indicating that it is not set
        return (ipString, 0)
    }

    /// Generate stable server ID (based on server content)
    /// - Parameters:
    ///   - name: server name
    ///   - address: server address
    ///   - port: server port
    /// - Returns: stable UUID string
    private func generateStableServerId(name: String, address: String, port: Int) -> String {
        // Generate stable identifier using server name, address and port
        let content = "\(name)|\(address)|\(port)"
        guard let data = content.data(using: .utf8) else {
            // Use a simple hash as fallback if encoding fails
            return UUID().uuidString
        }

        // Generate stable UUID using SHA256 hash
        let hash = SHA256.hash(data: data)
        var bytes = Array(hash.prefix(16)) // Use first 16 bytes

        // Set to UUID v5 format (based on SHA-1 namespace, here using the first 16 bytes of SHA256)
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // Version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant

        let uuid = bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
        return uuid.uuidString
    }

    /// Save the server address list to the game directory (save as servers.dat, NBT format)
    /// - Parameters:
    ///   - servers: server address list
    ///   - gameName: game name
    /// - Throws: Save errors
    func saveServerAddresses(_ servers: [ServerAddress], for gameName: String) async throws {
        let serversDatURL = AppPaths.profileDirectory(gameName: gameName)
            .appendingPathComponent("servers.dat")

        Logger.shared.debug("Start saving the server address list to: \(serversDatURL.path)")

        // Build NBT data structure
        // servers.dat structure:
        // TAG_Compound("")
        //   TAG_List("servers")
        //     TAG_Compound
        //       TAG_String("name") - server name
        //       TAG_String("ip") - Server address (format is "ip:port")
        //       TAG_Byte("hidden") - whether to hide (0 or 1)
        //       TAG_String("icon") - Server icon (optional, Base64 encoded)
        //       TAG_Byte("acceptTextures") - whether to accept textures (0 or 1)

        var serversList: [[String: Any]] = []

        for server in servers {
            var serverData: [String: Any] = [:]
            // Save fields in standard order
            serverData["name"] = server.name
            serverData["hidden"] = server.hidden ? Int8(1) : Int8(0)
            serverData["preventsChatReports"] = server.acceptTextures ? Int8(1) : Int8(0)
            // If the port is 0, only the address is saved, not the port
            if server.port > 0 {
                serverData["ip"] = "\(server.address):\(server.port)"
            } else {
                serverData["ip"] = server.address
            }

            // The icon field is only saved if it has a value
            if let icon = server.icon, !icon.isEmpty {
                serverData["icon"] = icon
            }

            serversList.append(serverData)
        }

        let nbtData: [String: Any] = [
            "servers": serversList
        ]

        // Encoded to NBT format (no compression used, Minecraft requires uncompressed NBT files)
        let encodedData = try NBTParser.encode(nbtData, compress: false)

        // Make sure the directory exists
        let directory = serversDatURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // write file
        try encodedData.write(to: serversDatURL)

        Logger.shared.debug("Successfully saved \(servers.count) server addresses to servers.dat")
    }
}

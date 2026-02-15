import Foundation

@preconcurrency import Dispatch
@preconcurrency import Network

/// Minecraft server information
struct MinecraftServerInfo: Codable {
    /// Server version information
    struct Version: Codable {
        let name: String
        let `protocol`: Int? // Use backticks because protocol is a Swift keyword
    }

    /// Player information
    struct Players: Codable {
        let max: Int
        let online: Int
        let sample: [Player]?

        struct Player: Codable {
            let name: String
            let id: String?
        }
    }

    /// Server Description (MOTD)
    struct Description: Codable {
        let text: String?
        let extra: [DescriptionElement]?

        /// description element (can be a string or a Description object)
        enum DescriptionElement: Codable {
            case string(String)
            case object(Description)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .string(string)
                } else {
                    let object = try container.decode(Description.self)
                    self = .object(object)
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let string):
                    try container.encode(string)
                case .object(let description):
                    try container.encode(description)
                }
            }

            var plainText: String {
                switch self {
                case .string(let string):
                    return string
                case .object(let description):
                    return description.plainText
                }
            }
        }

        /// Get plain text description (remove formatting code)
        var plainText: String {
            var result = ""
            if let text = text {
                result += stripFormatCodes(text)
            }
            if let extra = extra {
                result += extra.map { $0.plainText }.joined()
            }
            return result
        }

        /// Remove Minecraft formatting code
        private func stripFormatCodes(_ text: String) -> String {
            // Remove the § symbol and the format code that follows it
            var result = text
            while let range = result.range(of: "§") {
                let startIndex = range.lowerBound
                let endIndex = result.index(startIndex, offsetBy: 2, limitedBy: result.endIndex) ?? result.endIndex
                result.removeSubrange(startIndex..<endIndex)
            }
            return result
        }
    }

    let version: Version?
    let players: Players?
    let description: Description
    let favicon: String? // Base64 encoding icon
    let modinfo: ModInfo? // Mod information (if any)

    struct ModInfo: Codable {
        let type: String
        let modList: [Mod]?

        struct Mod: Codable {
            let modid: String
            let version: String
        }
    }
}

/// Minecraft Server List Ping protocol implementation
/// Use official protocol (1.7+) to obtain server information
enum MinecraftServerPing {
    /// Obtain server information using the Server List Ping protocol
    /// - Parameters:
    ///   - connectAddress: the actual connected address (SRV target or original address)
    ///   - connectPort: the actual connected port (SRV port or original port)
    ///   - originalAddress: original domain name (used for handshake)
    ///   - originalPort: original port (used for handshake)
    ///   - timeout: timeout (seconds), default 5 seconds
    /// - Returns: server information, nil if failed
    static func ping(
        connectAddress: String,
        connectPort: Int,
        originalAddress: String,
        originalPort: Int,
        timeout: TimeInterval = 5.0
    ) async -> MinecraftServerInfo? {
        // Create a TCP connection (using SRV target and port)
        let host = NWEndpoint.Host(connectAddress)
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(connectPort))
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        return await withCheckedContinuation { (continuation: CheckedContinuation<MinecraftServerInfo?, Never>) in
            final class State: @unchecked Sendable {
                private let lock = NSLock()
                private var _hasResumed = false
                private var _isTimeout = false
                var receivedData = Data()
                private var _timeoutTask: DispatchWorkItem?

                var hasResumed: Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return _hasResumed
                }

                var isTimeout: Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return _isTimeout
                }

                func setResumed() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if _hasResumed {
                        return false
                    }
                    _hasResumed = true
                    return true
                }

                func setTimeout() {
                    lock.lock()
                    defer { lock.unlock() }
                    _isTimeout = true
                }

                func setResumedAndTimeout() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if _hasResumed {
                        return false
                    }
                    _hasResumed = true
                    _isTimeout = true
                    return true
                }

                func setTimeoutTask(_ task: DispatchWorkItem?) {
                    lock.lock()
                    defer { lock.unlock() }
                    _timeoutTask = task
                }

                func cancelTimeoutTask() {
                    lock.lock()
                    defer { lock.unlock() }
                    _timeoutTask?.cancel()
                    _timeoutTask = nil
                }
            }
            let state = State()

            // Set timeout
            let timeoutTask = DispatchWorkItem { [weak state] in
                guard let state = state else { return }
                if state.setResumedAndTimeout() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            state.setTimeoutTask(timeoutTask)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

            // Function to receive data recursively
            func receiveData() {
                guard !state.hasResumed else { return }

                connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, _, isComplete, error in
                    guard !state.hasResumed else { return }

                    if error != nil {
                        if !state.isTimeout {
                            if state.setResumed() {
                                state.cancelTimeoutTask()
                                connection.cancel()
                                continuation.resume(returning: nil)
                            }
                        }
                        return
                    }

                    if let data = data, !data.isEmpty {
                        state.receivedData.append(data)

                        // Try to parse the response
                        if let serverInfo = parseResponse(data: state.receivedData) {
                            if state.setResumed() {
                                state.cancelTimeoutTask()
                                connection.cancel()
                                continuation.resume(returning: serverInfo)
                            }
                        } else if isComplete {
                            // Data reception completed but parsing failed
                            if state.setResumed() {
                                state.cancelTimeoutTask()
                                Logger.shared.debug("解析服务器响应失败: \(connectAddress):\(connectPort)")
                                connection.cancel()
                                continuation.resume(returning: nil)
                            }
                        } else {
                            // Continue to receive data
                            receiveData()
                        }
                    } else if isComplete {
                        // no more data
                        if state.setResumed() {
                            state.cancelTimeoutTask()
                            connection.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }

            // Start receiving data
            receiveData()

            // Set connection status change callback
            connection.stateUpdateHandler = { [weak state] stateUpdate in
                guard let state = state else { return }
                guard !state.hasResumed else { return }

                switch stateUpdate {
                case .ready:
                    // The connection is successful and a handshake packet and status request packet are sent (using the original address and port)
                    sendHandshakeAndStatusRequest(connection: connection, address: originalAddress, port: originalPort)
                case .failed(let error):
                    if !state.isTimeout {
                        if state.setResumed() {
                            state.cancelTimeoutTask()
                            Logger.shared.debug("服务器连接失败: \(connectAddress):\(connectPort) - \(error.localizedDescription)")
                            connection.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                case .waiting:
                    // Waiting for connection, no need to log
                    break
                case .cancelled:
                    if !state.hasResumed && !state.isTimeout {
                        if state.setResumed() {
                            state.cancelTimeoutTask()
                            continuation.resume(returning: nil)
                        }
                    }
                default:
                    break
                }
            }

            // Start connection
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    /// Send handshake packet and status request packet
    private static func sendHandshakeAndStatusRequest(connection: NWConnection, address: String, port: Int) {
        var packetData = Data()

        // 1. Send Handshake package (package ID 0x00)
        // Packet ID: 0x00 (VarInt)
        packetData.append(encodeVarInt(0))

        // Protocol version: -1 (VarInt) - indicates status query
        packetData.append(encodeVarInt(-1))

        // Server address (String)
        packetData.append(encodeString(address))

        // Server port (Unsigned Short)
        let portBytes = withUnsafeBytes(of: UInt16(port).bigEndian) { Data($0) }
        packetData.append(portBytes)

        // Next state: 1 (VarInt) - represents the state
        packetData.append(encodeVarInt(1))

        // Send handshake packet
        let handshakeLength = encodeVarInt(Int32(packetData.count))
        let handshakePacket = handshakeLength + packetData
        connection.send(content: handshakePacket, completion: .contentProcessed { error in
            if let error = error {
                Logger.shared.debug("发送握手包失败: \(error.localizedDescription)")
                return
            }

            // 2. Send Status Request packet (packet ID 0x00)
            var statusRequestData = Data()
            statusRequestData.append(encodeVarInt(0)) // Package ID: 0x00

            let statusRequestLength = encodeVarInt(Int32(statusRequestData.count))
            let statusRequestPacket = statusRequestLength + statusRequestData
            connection.send(content: statusRequestPacket, completion: .contentProcessed { error in
                if let error = error {
                    Logger.shared.debug("发送状态请求包失败: \(error.localizedDescription)")
                }
            })
        })
    }

    /// Parse server response
    private static func parseResponse(data: Data) -> MinecraftServerInfo? {
        var offset = 0

        guard data.count > offset else { return nil }

        // Read packet length (VarInt)
        guard let (packetLength, lengthBytes) = decodeVarInt(data: data, offset: &offset) else {
            return nil
        }

        // Check if the data is complete
        let totalLength = lengthBytes + Int(packetLength)
        guard data.count >= totalLength else {
            return nil // The data is incomplete, keep waiting
        }

        // Read package ID (VarInt)
        guard let (packetId, _) = decodeVarInt(data: data, offset: &offset) else {
            return nil
        }

        // The package ID of the Status Response package should be 0x00
        guard packetId == 0 else {
            return nil
        }

        // Read JSON string
        guard let (jsonString, _) = decodeString(data: data, offset: &offset) else {
            return nil
        }

        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let serverInfo = try decoder.decode(MinecraftServerInfo.self, from: jsonData)
            return serverInfo
        } catch {
            // Log when JSON parsing fails (may be due to protocol incompatibility)
            Logger.shared.debug("解析服务器 JSON 失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - VarInt encoding/decoding

    /// Encoding VarInt
    private static func encodeVarInt(_ value: Int32) -> Data {
        var result = Data()
        var val = UInt32(bitPattern: value)

        while true {
            var byte = UInt8(val & 0x7F)
            val >>= 7
            if val != 0 {
                byte |= 0x80
            }
            result.append(byte)
            if val == 0 {
                break
            }
        }

        return result
    }

    /// Decode VarInt
    private static func decodeVarInt(data: Data, offset: inout Int) -> (Int32, Int)? {
        guard offset < data.count else { return nil }

        var result: UInt32 = 0
        var shift = 0
        var bytesRead = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            bytesRead += 1

            result |= UInt32(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                break
            }

            shift += 7
            if shift >= 32 {
                return nil // VarInt overflow
            }
        }

        return (Int32(bitPattern: result), bytesRead)
    }

    // MARK: - String encoding/decoding

    /// Encoded string (UTF-8, prepended with VarInt length)
    private static func encodeString(_ string: String) -> Data {
        guard let utf8Data = string.data(using: .utf8) else {
            return encodeVarInt(0) // empty string
        }

        var result = Data()
        result.append(encodeVarInt(Int32(utf8Data.count)))
        result.append(utf8Data)
        return result
    }

    /// decode string
    private static func decodeString(data: Data, offset: inout Int) -> (String, Int)? {
        guard let (length, lengthBytes) = decodeVarInt(data: data, offset: &offset) else {
            return nil
        }

        guard length >= 0 else { return nil }
        guard offset + Int(length) <= data.count else {
            // Data is incomplete, restore offset
            offset -= lengthBytes
            return nil
        }

        let stringData = data.subdata(in: offset..<(offset + Int(length)))
        offset += Int(length)

        guard let string = String(data: stringData, encoding: .utf8) else {
            return nil
        }

        return (string, lengthBytes + Int(length))
    }
}

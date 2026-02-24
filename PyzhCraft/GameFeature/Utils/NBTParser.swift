import Foundation

/// NBT tag type
private enum NBTType: UInt8 {
    case end = 0
    case byte = 1
    case short = 2
    case int = 3
    case long = 4
    case float = 5
    case double = 6
    case byteArray = 7
    case string = 8
    case list = 9
    case compound = 10
    case intArray = 11
    case longArray = 12
}

/// NBT parser
/// Used to parse and generate Minecraft NBT format files (such as servers.dat)
class NBTParser {
    private var data: Data
    private var offset: Int = 0
    private var outputData = Data()
    
    init(data: Data) {
        self.data = data
    }
    
    /// Create an NBT parser for writing
    private init() {
        self.data = Data()
    }
    
    /// Parse NBT data (supports GZIP compression)
    /// - Returns: parsed dictionary
    /// - Throws: Parsing errors
    func parse() throws -> [String: Any] {
        // Check if it is GZIP compression
        if data.count >= 2 && data[0] == 0x1F && data[1] == 0x8B {
            // GZIP compression, decompress first
            data = try decompressGzip(data: data)
            offset = 0
        }
        
        // Read the root tag type (should be TAG_Compound)
        guard !data.isEmpty else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Empty Data",
                level: .notification
            )
        }
        
        let tagType = NBTType(rawValue: data[offset]) ?? .end
        guard tagType == .compound else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Invalid Root",
                level: .notification
            )
        }
        
        offset += 1
        
        // Read tag name (root tag name may be empty)
        _ = try readString()
        
        // Read Compound content
        return try readCompound() as [String: Any]
    }
    
    /// Read string
    private func readString() throws -> String {
        guard offset + 2 <= data.count else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Insufficient Data",
                level: .notification
            )
        }
        
        let length = Int(readShort())
        guard offset + length <= data.count else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT String Out Of Range",
                level: .notification
            )
        }
        
        let stringData = data.subdata(in: offset..<(offset + length))
        offset += length
        
        return String(data: stringData, encoding: .utf8) ?? ""
    }
    
    /// Read short integer (2 bytes, big endian)
    private func readShort() -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let value = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        offset += 2
        return value
    }
    
    /// Read integer (4 bytes, big endian)
    private func readInt() -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: Int32 = 0
        for i in 0..<4 {
            value = (value << 8) | Int32(data[offset + i])
        }
        offset += 4
        return value
    }
    
    /// Read bytes
    private func readByte() -> UInt8 {
        guard offset < data.count else { return 0 }
        let value = data[offset]
        offset += 1
        return value
    }
    
    /// Read the Compound tag
    private func readCompound() throws -> [String: Any] {
        var result: [String: Any] = [:]
        
        while offset < data.count {
            let tagType = NBTType(rawValue: data[offset]) ?? .end
            offset += 1
            
            if tagType == .end {
                break
            }
            
            let name = try readString()
            let value = try readTagValue(type: tagType)
            result[name] = value
        }
        
        return result
    }
    
    /// Read tag value
    private func readTagValue(type: NBTType) throws -> Any {
        switch type {
        case .byte:
            return Int8(bitPattern: readByte())
        case .short:
            return Int16(bitPattern: readShort())
        case .int:
            return readInt()
        case .long:
            return readLong()
        case .float:
            return readFloat()
        case .double:
            return readDouble()
        case .string:
            return try readString()
        case .list:
            return try readList()
        case .compound:
            return try readCompound()
        case .byteArray:
            let length = Int(readInt())
            guard offset + length <= data.count else {
                throw GlobalError(type: .fileSystem, i18nKey: "NBT Byte Array Out Of Range", level: .notification)
            }
            let array = Array(data.subdata(in: offset..<(offset + length)))
            offset += length
            return array
        case .intArray:
            let length = Int(readInt())
            var array: [Int32] = []
            for _ in 0..<length {
                array.append(readInt())
            }
            return array
        case .longArray:
            let length = Int(readInt())
            var array: [Int64] = []
            for _ in 0..<length {
                array.append(readLong())
            }
            return array
        case .end:
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Unexpected End Tag",
                level: .notification
            )
        }
    }
    
    /// Read long integer (8 bytes, big endian)
    private func readLong() -> Int64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: Int64 = 0
        for i in 0..<8 {
            value = (value << 8) | Int64(data[offset + i])
        }
        offset += 8
        return value
    }
    
    /// Read floating point number (4 bytes, IEEE 754)
    private func readFloat() -> Float {
        guard offset + 4 <= data.count else { return 0 }
        let intValue = readInt()
        return Float(bitPattern: UInt32(bitPattern: intValue))
    }
    
    /// Read double-precision floating point number (8 bytes, IEEE 754)
    private func readDouble() -> Double {
        guard offset + 8 <= data.count else { return 0 }
        let longValue = readLong()
        return Double(bitPattern: UInt64(bitPattern: longValue))
    }
    
    /// Read list
    private func readList() throws -> [Any] {
        guard offset < data.count else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Insufficient Data For List",
                level: .notification
            )
        }
        
        let listType = NBTType(rawValue: data[offset]) ?? .end
        offset += 1
        
        let length = Int(readInt())
        var result: [Any] = []
        
        for _ in 0..<length {
            let value = try readTagValue(type: listType)
            result.append(value)
        }
        
        return result
    }
    
    /// Decompress GZIP data (using system commands)
    private func decompressGzip(data: Data) throws -> Data {
        guard !data.isEmpty else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Empty Data",
                level: .notification
            )
        }
        
        // Create temporary files to store compressed data
        let tempDir = FileManager.default.temporaryDirectory
        let tempInputFile = tempDir.appendingPathComponent(UUID().uuidString + ".gz")
        let tempOutputFile = tempDir.appendingPathComponent(UUID().uuidString)
        
        defer {
            // Clean temporary files
            try? FileManager.default.removeItem(at: tempInputFile)
            try? FileManager.default.removeItem(at: tempOutputFile)
        }
        
        // Write compressed data to temporary file
        try data.write(to: tempInputFile)
        
        // Unzip using the system gzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", tempInputFile.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
        } catch {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Process Start Failed",
                level: .notification
            )
        }
        
        // Read decompressed data
        let fileHandle = pipe.fileHandleForReading
        let decompressedData = fileHandle.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Decompress Failed",
                level: .notification
            )
        }
        
        guard !decompressedData.isEmpty else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Decompressed Empty",
                level: .notification
            )
        }
        
        return decompressedData
    }
    
    // MARK: - NBT writing method
    
    /// Encode dictionary data into NBT format (supports GZIP compression)
    /// - Parameters:
    ///   - data: dictionary data to be encoded
    ///   - compress: whether to use GZIP compression, default true
    /// - Returns: encoded NBT data
    /// - Throws: Encoding error
    static func encode(_ data: [String: Any], compress: Bool = true) throws -> Data {
        let parser = NBTParser()
        parser.outputData = Data()
        
        // Write root tag type (TAG_Compound)
        parser.writeByte(NBTType.compound.rawValue)
        
        // Write root tag name (empty string)
        parser.writeString("")
        
        // Write Compound content
        try parser.writeCompound(data)
        
        // If compression is enabled, use gzip compression
        if compress {
            return try parser.compressGzip(data: parser.outputData)
        }
        
        return parser.outputData
    }
    
    /// write bytes
    private func writeByte(_ value: UInt8) {
        outputData.append(value)
    }
    
    /// Write short integer (2 bytes, big endian)
    private func writeShort(_ value: UInt16) {
        outputData.append(UInt8((value >> 8) & 0xFF))
        outputData.append(UInt8(value & 0xFF))
    }
    
    /// Write integer (4 bytes, big endian)
    private func writeInt(_ value: Int32) {
        outputData.append(UInt8((value >> 24) & 0xFF))
        outputData.append(UInt8((value >> 16) & 0xFF))
        outputData.append(UInt8((value >> 8) & 0xFF))
        outputData.append(UInt8(value & 0xFF))
    }
    
    /// Write long (8 bytes, big endian)
    private func writeLong(_ value: Int64) {
        outputData.append(UInt8((value >> 56) & 0xFF))
        outputData.append(UInt8((value >> 48) & 0xFF))
        outputData.append(UInt8((value >> 40) & 0xFF))
        outputData.append(UInt8((value >> 32) & 0xFF))
        outputData.append(UInt8((value >> 24) & 0xFF))
        outputData.append(UInt8((value >> 16) & 0xFF))
        outputData.append(UInt8((value >> 8) & 0xFF))
        outputData.append(UInt8(value & 0xFF))
    }
    
    /// write string
    private func writeString(_ value: String) {
        let stringData = value.data(using: .utf8) ?? Data()
        let length = UInt16(stringData.count)
        writeShort(length)
        outputData.append(stringData)
    }
    
    /// Write floating point number (4 bytes, IEEE 754)
    private func writeFloat(_ value: Float) {
        let bitPattern = value.bitPattern
        // Convert the bit pattern of a UInt32 to an Int32 (leaving the bit pattern unchanged)
        let intValue = Int32(bitPattern: bitPattern)
        writeInt(intValue)
    }
    
    /// Write a double-precision floating point number (8 bytes, IEEE 754)
    private func writeDouble(_ value: Double) {
        let bitPattern = value.bitPattern
        // Convert the bit pattern of UInt64 to Int64 (leaving the bit pattern unchanged)
        let longValue = Int64(bitPattern: bitPattern)
        writeLong(longValue)
    }
    
    /// Write Compound tag
    private func writeCompound(_ compound: [String: Any]) throws {
        for (name, value) in compound {
            let tagType = try inferNBTType(from: value)
            writeByte(tagType.rawValue)
            writeString(name)
            try writeTagValue(type: tagType, value: value)
        }
        // Write End tag
        writeByte(NBTType.end.rawValue)
    }
    
    /// Write tag value
    private func writeTagValue(type: NBTType, value: Any) throws {
        switch type {
        case .byte:
            if let intValue = value as? Int {
                writeByte(UInt8(bitPattern: Int8(intValue)))
            } else if let int8Value = value as? Int8 {
                writeByte(UInt8(bitPattern: int8Value))
            } else if let boolValue = value as? Bool {
                writeByte(boolValue ? 1 : 0)
            } else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Byte Value",
                    level: .notification
                )
            }
        case .short:
            let shortValue: Int16
            if let intValue = value as? Int {
                shortValue = Int16(intValue)
            } else if let int16Value = value as? Int16 {
                shortValue = int16Value
            } else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Short Value",
                    level: .notification
                )
            }
            writeShort(UInt16(bitPattern: shortValue))
        case .int:
            let intValue: Int32
            if let int = value as? Int {
                intValue = Int32(int)
            } else if let int32Value = value as? Int32 {
                intValue = int32Value
            } else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Int Value",
                    level: .notification
                )
            }
            writeInt(intValue)
        case .long:
            let longValue: Int64
            if let int = value as? Int {
                longValue = Int64(int)
            } else if let int64Value = value as? Int64 {
                longValue = int64Value
            } else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Long Value",
                    level: .notification
                )
            }
            writeLong(longValue)
        case .float:
            guard let floatValue = value as? Float else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Float Value",
                    level: .notification
                )
            }
            writeFloat(floatValue)
        case .double:
            guard let doubleValue = value as? Double else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Double Value",
                    level: .notification
                )
            }
            writeDouble(doubleValue)
        case .string:
            let stringValue: String
            if let str = value as? String {
                stringValue = str
            } else {
                stringValue = String(describing: value)
            }
            writeString(stringValue)
        case .list:
            try writeList(value)
        case .compound:
            guard let compoundValue = value as? [String: Any] else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Compound Value",
                    level: .notification
                )
            }
            try writeCompound(compoundValue)
        case .byteArray:
            guard let array = value as? [UInt8] else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Byte Array Value",
                    level: .notification
                )
            }
            writeInt(Int32(array.count))
            outputData.append(contentsOf: array)
        case .intArray:
            guard let array = value as? [Int32] else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Int Array Value",
                    level: .notification
                )
            }
            writeInt(Int32(array.count))
            for item in array {
                writeInt(item)
            }
        case .longArray:
            guard let array = value as? [Int64] else {
                throw GlobalError(
                    type: .fileSystem,
                    i18nKey: "NBT Invalid Long Array Value",
                    level: .notification
                )
            }
            writeInt(Int32(array.count))
            for item in array {
                writeLong(item)
            }
        case .end:
            break
        }
    }
    
    /// write list
    private func writeList(_ value: Any) throws {
        guard let array = value as? [Any], !array.isEmpty else {
            // Empty list, write type is End, length is 0
            writeByte(NBTType.end.rawValue)
            writeInt(0)
            return
        }
        
        // Infer list element type
        let elementType = try inferNBTType(from: array[0])
        writeByte(elementType.rawValue)
        writeInt(Int32(array.count))
        
        for item in array {
            try writeTagValue(type: elementType, value: item)
        }
    }
    
    /// Infer NBT type from value
    private func inferNBTType(from value: Any) throws -> NBTType {
        switch value {
        case is Bool, is Int8:
            return .byte
        case is Int16:
            return .short
        case is Int32, is Int:
            return .int
        case is Int64:
            return .long
        case is Float:
            return .float
        case is Double:
            return .double
        case is String:
            return .string
        case is [UInt8]:
            return .byteArray
        case is [Int32]:
            return .intArray
        case is [Int64]:
            return .longArray
        case is [Any]:
            return .list
        case is [String: Any]:
            return .compound
        default:
            // Default converted to string
            return .string
        }
    }
    
    /// Compress GZIP data (using system commands)
    private func compressGzip(data: Data) throws -> Data {
        guard !data.isEmpty else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT Empty Data For Compress",
                level: .notification
            )
        }
        
        // Create temporary files to store uncompressed data
        let tempDir = FileManager.default.temporaryDirectory
        let tempInputFile = tempDir.appendingPathComponent(UUID().uuidString)
        let tempOutputFile = tempDir.appendingPathComponent(UUID().uuidString + ".gz")
        
        defer {
            // Clean temporary files
            try? FileManager.default.removeItem(at: tempInputFile)
            try? FileManager.default.removeItem(at: tempOutputFile)
        }
        
        // Write uncompressed data to temporary file
        try data.write(to: tempInputFile)
        
        // Compress using the system gzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", tempInputFile.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
        } catch {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Compress Process Start Failed",
                level: .notification
            )
        }
        
        // Read compressed data
        let fileHandle = pipe.fileHandleForReading
        let compressedData = fileHandle.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Compress Failed",
                level: .notification
            )
        }
        
        guard !compressedData.isEmpty else {
            throw GlobalError(
                type: .fileSystem,
                i18nKey: "NBT GZIP Compressed Empty",
                level: .notification
            )
        }
        
        return compressedData
    }
}

import Foundation

class AppCacheManager {
    static let shared = AppCacheManager()
    private let queue = DispatchQueue(label: "AppCacheManager.queue")

    private func fileURL(for namespace: String) throws -> URL {

        do {
            try FileManager.default.createDirectory(at: AppPaths.appCache, withIntermediateDirectories: true)
        } catch {
            throw GlobalError.fileSystem(i18nKey: "Cache Directory Creation Failed",
                level: .notification
            )
        }

        return AppPaths.appCache.appendingPathComponent("\(namespace).json")
    }

    // MARK: - Public API

    /// - Parameters:
    ///   - namespace: namespace
    ///   - key: key
    ///   - value: value
    /// - Throws: GlobalError when the operation fails
    func set<T: Codable>(namespace: String, key: String, value: T) throws {
        try queue.sync {
            var nsDict = try loadNamespace(namespace)

            do {
                let data = try JSONEncoder().encode(value)
                nsDict[key] = data
                try saveNamespace(namespace, dict: nsDict)
            } catch {
                throw GlobalError.validation(i18nKey: "Cache Data Encode Failed",
                    level: .notification
                )
            }
        }
    }

    /// - Parameters:
    ///   - namespace: namespace
    ///   - key: key
    ///   - value: value
    func setSilently<T: Codable>(namespace: String, key: String, value: T) {
        do {
            try set(namespace: namespace, key: key, value: value)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Get cached value
    /// - Parameters:
    ///   - namespace: namespace
    ///   - key: key
    ///   - type: expected type
    /// - Returns: decoded value, returns nil if it does not exist or decoding fails
    func get<T: Codable>(namespace: String, key: String, as type: T.Type) -> T? {
        return queue.sync {
            do {
                let nsDict = try loadNamespace(namespace)
                guard let data = nsDict[key] else { return nil }

                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    GlobalErrorHandler.shared.handle(GlobalError.validation(i18nKey: "Cache Data Decode Failed",
                        level: .silent
                    ))
                    return nil
                }
            } catch {
                GlobalErrorHandler.shared.handle(error)
                return nil
            }
        }
    }

    /// Remove cached items
    /// - Parameters:
    ///   - namespace: namespace
    ///   - key: key
    /// - Throws: GlobalError when the operation fails
    func remove(namespace: String, key: String) throws {
        try queue.sync {
            var nsDict = try loadNamespace(namespace)
            nsDict.removeValue(forKey: key)
            try saveNamespace(namespace, dict: nsDict)
        }
    }

    /// Remove cached items (silent version)
    /// - Parameters:
    ///   - namespace: namespace
    ///   - key: key
    func removeSilently(namespace: String, key: String) {
        do {
            try remove(namespace: namespace, key: key)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Clear the cache of the specified namespace
    /// - Parameter namespace: namespace
    /// - Throws: GlobalError when the operation fails
    func clear(namespace: String) throws {
        try queue.sync {
            try saveNamespace(namespace, dict: [:])
        }
    }

    /// Clear the cache of the specified namespace (silent version)
    /// - Parameter namespace: namespace
    func clearSilently(namespace: String) {
        do {
            try clear(namespace: namespace)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Clear all cache
    /// - Throws: GlobalError when the operation fails
    func clearAll() throws {
        try queue.sync {

            do {
                let files = try FileManager.default.contentsOfDirectory(at: AppPaths.appCache, includingPropertiesForKeys: nil)
                for file in files where file.pathExtension == "json" {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                throw GlobalError.fileSystem(i18nKey: "Cache Clear Failed",
                    level: .notification
                )
            }
        }
    }

    /// Clear all caches (silent version)
    func clearAllSilently() {
        do {
            try clearAll()
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    // MARK: - Persistence

    /// Load namespace data
    /// - Parameter namespace: namespace
    /// - Returns: namespace data dictionary
    /// - Throws: GlobalError when the operation fails
    private func loadNamespace(_ namespace: String) throws -> [String: Data] {
        let url = try fileURL(for: namespace)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            throw GlobalError.fileSystem(i18nKey: "Cache Read Failed",
                level: .notification
            )
        }
    }

    /// Save namespace data
    /// - Parameters:
    ///   - namespace: namespace
    ///   - dict: the data dictionary to be saved
    /// - Throws: GlobalError when the operation fails
    private func saveNamespace(_ namespace: String, dict: [String: Data]) throws {
        let url = try fileURL(for: namespace)

        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: url)
        } catch {
            throw GlobalError.fileSystem(i18nKey: "Cache Write Failed",
                level: .notification
            )
        }
    }
}

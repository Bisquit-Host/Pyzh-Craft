import SwiftUI
import Combine

/// Game Icon Cache Manager
/// Icon caching to avoid duplicate file system accesses
/// Use @unchecked Sendable because thread safety has been ensured through DispatchQueue
final class GameIconCache: @unchecked Sendable {
    static let shared = GameIconCache()
    
    /// Icon file existence cache: key is "gameName/iconName", value is whether it exists
    private let existenceCache = NSCache<NSString, NSNumber>()
    
    /// Icon URL cache: key is "gameName/iconName", value is icon URL
    private let urlCache = NSCache<NSString, NSURL>()
    
    /// Cache access queue to ensure thread safety
    private let cacheQueue = DispatchQueue(label: "com.pyzhcraft.gameiconcache", attributes: .concurrent)
    
    /// Cache invalidation notification: Send notification when cache is cleared
    /// key is the game name, nil means clear all caches
    private let cacheInvalidationSubject = PassthroughSubject<String?, Never>()
    
    /// Cache invalidation notification publisher
    var cacheInvalidationPublisher: AnyPublisher<String?, Never> {
        cacheInvalidationSubject.eraseToAnyPublisher()
    }
    
    private init() {
        // Set cache limits
        existenceCache.countLimit = 100
        urlCache.countLimit = 100
    }
    
    /// Get the URL of the game icon
    /// - Parameters:
    ///   - gameName: game name
    ///   - iconName: icon file name
    /// - Returns: URL of the icon
    func iconURL(gameName: String, iconName: String) -> URL {
        let cacheKey = "\(gameName)/\(iconName)" as NSString
        
        return cacheQueue.sync {
            if let cachedURL = urlCache.object(forKey: cacheKey) {
                return cachedURL as URL
            }
            
            let profileDir = AppPaths.profileDirectory(gameName: gameName)
            let iconURL = profileDir.appendingPathComponent(iconName)
            urlCache.setObject(iconURL as NSURL, forKey: cacheKey)
            return iconURL
        }
    }
    
    /// Check if icon file exists (with cache)
    /// - Parameters:
    ///   - gameName: game name
    ///   - iconName: icon file name
    /// - Returns: Whether the icon file exists
    func iconExists(gameName: String, iconName: String) -> Bool {
        let cacheKey = "\(gameName)/\(iconName)" as NSString
        
        return cacheQueue.sync {
            if let cached = existenceCache.object(forKey: cacheKey) {
                return cached.boolValue
            }
            
            let iconURL = self.iconURL(gameName: gameName, iconName: iconName)
            let exists = FileManager.default.fileExists(atPath: iconURL.path)
            existenceCache.setObject(NSNumber(value: exists), forKey: cacheKey)
            return exists
        }
    }
    // swiftlint:disable:next discouraged_optional_boolean
    func cachedIconExists(gameName: String, iconName: String) -> Bool? {
        let cacheKey = "\(gameName)/\(iconName)" as NSString
        
        return cacheQueue.sync {
            if let cached = existenceCache.object(forKey: cacheKey) {
                return cached.boolValue
            }
            return nil
        }
    }
    
    /// Asynchronously checks whether the icon file exists (executed on a background thread)
    /// - Parameters:
    ///   - gameName: game name
    ///   - iconName: icon file name
    /// - Returns: Whether the icon file exists
    func iconExistsAsync(gameName: String, iconName: String) async -> Bool {
        let cacheKeyString = "\(gameName)/\(iconName)"
        
        // Check the cache first (check synchronously on the main thread to avoid Sendable problems)
        let cacheKey = cacheKeyString as NSString
        let cached = cacheQueue.sync {
            existenceCache.object(forKey: cacheKey)
        }
        
        if let cached = cached {
            return cached.boolValue
        }
        
        // Check file existence on background thread
        let exists = await Task.detached(priority: .utility) {
            // Get the URL on a background thread (does not rely on self)
            let profileDir = AppPaths.profileDirectory(gameName: gameName)
            let iconURL = profileDir.appendingPathComponent(iconName)
            return FileManager.default.fileExists(atPath: iconURL.path)
        }.value
        
        // Update cache (performed in main thread or queue to avoid Sendable issues)
        // Use String instead of NSString, convert inside closure, avoid Sendable issues
        let existsValue = exists
        cacheQueue.async(flags: .barrier) {
            let cacheKey = cacheKeyString as NSString
            self.existenceCache.setObject(NSNumber(value: existsValue), forKey: cacheKey)
        }
        
        return exists
    }
    
    /// Clear the icon cache for a specific game
    /// - Parameter gameName: game name
    func invalidateCache(for gameName: String) {
        cacheQueue.async(flags: .barrier) {
            // NSCache does not have allKeys, you need to manually maintain the key list or use other methods
            // Simplified processing: clear the cache directly
            // If finer control is required, a separate set of keys can be maintained
            self.existenceCache.removeAllObjects()
            self.urlCache.removeAllObjects()
            
            // Send cache invalidation notification
            DispatchQueue.main.async {
                self.cacheInvalidationSubject.send(gameName)
            }
        }
    }
    
    /// clear all cache
    func clearAllCache() {
        cacheQueue.async(flags: .barrier) {
            self.existenceCache.removeAllObjects()
            self.urlCache.removeAllObjects()
            
            // Send cache invalidation notification (nil means clear all caches)
            DispatchQueue.main.async {
                self.cacheInvalidationSubject.send(nil)
            }
        }
    }
}

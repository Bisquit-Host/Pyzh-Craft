import Foundation

/// Genuine Account Tag Manager
/// Mark whether a genuine account has been added and determine whether adding an offline account is allowed
@MainActor
class PremiumAccountFlagManager {
    static let shared = PremiumAccountFlagManager()
    
    private let flagKey = "hasAddedPremiumAccount"
    
    private init() {}
    
    /// Check whether a genuine account has been added before
    /// - Returns: Returns true if a genuine account has been added before
    func hasAddedPremiumAccount() -> Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }
    
    /// Set the genuine account mark added
    func setPremiumAccountAdded() {
        UserDefaults.standard.set(true, forKey: flagKey)
        Logger.shared.debug("A genuine account has been set up to add a mark")
    }
    
    /// Clear genuine account mark (for testing or reset)
    func clearPremiumAccountFlag() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        Logger.shared.debug("Genuine account mark cleared")
    }
}

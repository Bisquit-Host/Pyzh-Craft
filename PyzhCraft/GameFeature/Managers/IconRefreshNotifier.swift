import Foundation
import Combine

/// Icon refresh notification manager
/// Notification view refreshes after icon update
final class IconRefreshNotifier: ObservableObject {
    static let shared = IconRefreshNotifier()
    
    /// Icon refresh notification to publisher
    /// Send the game name, nil means refresh all icons
    private let refreshSubject = PassthroughSubject<String?, Never>()
    
    /// Publisher of icon refresh notification
    var refreshPublisher: AnyPublisher<String?, Never> {
        refreshSubject.eraseToAnyPublisher()
    }
    
    private init() {}
    
    /// Notification to refresh the icon of a specific game
    /// - Parameter gameName: game name, nil means refresh all icons
    func notifyRefresh(for gameName: String?) {
        refreshSubject.send(gameName)
    }
    
    /// Notification refresh all icons
    func notifyRefreshAll() {
        refreshSubject.send(nil)
    }
}

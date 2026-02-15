import Combine
import Foundation

/// work path provider
public protocol WorkingPathProviding: AnyObject {
    /// The current launcher working directory; an empty string uses the default directory
    var currentWorkingPath: String { get }
    var workingPathWillChange: AnyPublisher<Void, Never> { get }
}

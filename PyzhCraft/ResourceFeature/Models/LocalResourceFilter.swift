import Foundation

/// Local resource filter type
enum LocalResourceFilter: String, CaseIterable, Identifiable {
    case all, disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "resource.local_filter.all".localized()
        case .disabled:
            return "resource.local_filter.disabled".localized()
        }
    }
}

import SwiftUI

/// Error popup modifier
struct ErrorAlertModifier: ViewModifier {
    @StateObject private var errorHandler = GlobalErrorHandler.shared

    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.notificationTitle ?? "",
                isPresented: .constant(errorHandler.currentError != nil && errorHandler.currentError?.level == .popup)
            ) {
                Button("common.close".localized()) {
                    errorHandler.clearCurrentError()
                }
            } message: {
                if let error = errorHandler.currentError {
                    Text(error.localizedDescription)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Add error popup window handling
    func errorAlert() -> some View {
        self.modifier(ErrorAlertModifier())
    }
}

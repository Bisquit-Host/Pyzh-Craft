import SwiftUI

struct MinecraftAuthView: View {
    @StateObject private var authService = MinecraftAuthService.shared
    var onLoginSuccess: ((MinecraftProfileResponse) -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Authentication status display
            switch authService.authState {
            case .notAuthenticated:
                notAuthenticatedView
//                waitingForBrowserAuthView
            case .waitingForBrowserAuth:
                waitingForBrowserAuthView

            case .processingAuthCode:
                processingAuthCodeView

            case .authenticated(let profile):
                authenticatedView(profile: profile)

            case .error(let message):
                errorView(message: message)
            }
        }
        .padding()
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Reset authentication service status (if authentication is not completed)
        if case .notAuthenticated = authService.authState {
            authService.isLoading = false
        }
        // The status is not cleared when authentication is successful, and authentication information may still be required
    }

    // MARK: - Uncertified status
    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 46))
                .symbolRenderingMode(.multicolor)
                .symbolVariant(.none)
                .foregroundColor(.secondary)
            Text("minecraft.auth.title".localized())
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("minecraft.auth.subtitle".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Wait for browser authorization status
    private var waitingForBrowserAuthView: some View {
        VStack(spacing: 16) {
            // browser icon
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 46))
                .foregroundColor(.secondary)

            Text("minecraft.auth.waiting_browser".localized())
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("minecraft.auth.waiting_browser.subtitle".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Handle authorization code status
    private var processingAuthCodeView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.small)

            Text("minecraft.auth.processing.title".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("minecraft.auth.processing.subtitle".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Authentication success status
    private func authenticatedView(
        profile: MinecraftProfileResponse
    ) -> some View {
        VStack(spacing: 20) {
            // User avatar
            if let skinUrl = profile.skins.first?.url {
                MinecraftSkinUtils(type: .url, src: skinUrl.httpToHttps())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    )
            }

            VStack(spacing: 8) {
                Text("minecraft.auth.success".localized())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)

                Text(profile.name)
                    .font(.headline)

                Text(
                    String(
                        format: "minecraft.auth.uuid".localized(),
                        profile.id
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            }

            Text("minecraft.auth.confirm_login".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - error status
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("minecraft.auth.failed".localized())
                .font(.headline)
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("minecraft.auth.retry_message".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    MinecraftAuthView()
}

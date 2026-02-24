import SwiftUI

struct AddPlayerSheetView: View {
    @Binding var playerName: String
    @Binding var isPlayerNameValid: Bool
    var onAdd: () -> Void
    var onCancel: () -> Void
    var onLogin: (MinecraftProfileResponse) -> Void
    
    enum PlayerProfile {
        case minecraft(MinecraftProfileResponse)
    }
    
    @ObservedObject var playerListViewModel: PlayerListViewModel
    
    @State private var isPremium = false
    @State private var authenticatedProfile: MinecraftProfileResponse?
    @StateObject private var authService = MinecraftAuthService.shared
    
    @Environment(\.openURL)
    private var openURL
    @State private var selectedAuthType: AccountAuthType = .premium
    @FocusState private var isTextFieldFocused: Bool
    @State private var showErrorPopover = false
    
    // Mark check status
    @State private var isCheckingFlag = true  // Initially true, loading will be displayed directly when entering the page
    // IP check results (only used if there is no genuine account in the list and there is no mark)
    @State private var isForeignIP = false
    
    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("Add Account")
                        .font(.headline)
                    
                    Spacer()
                    
                    if isCheckingFlag {
                        ProgressView()
                            .controlSize(.small)
                            .frame(height: 20.5) // Set a fixed height consistent with Picker
                            .padding(.trailing, 10)
                    } else {
                        Picker("", selection: $selectedAuthType) {
                            ForEach(availableAuthTypes) {
                                Text($0.displayName)
                                    .tag($0)
                            }
                        }
                        .pickerStyle(.menu)  // Use drop-down menu style
                        .labelStyle(.titleOnly)
                        .fixedSize()
                    }
                }
            }, body: {
                switch selectedAuthType {
                case .premium:
                    MinecraftAuthView(onLoginSuccess: onLogin)
                    
                case .offline:
                    VStack(alignment: .leading) {
                        playerInfoSection
                            .padding(.bottom, 10)
                        
                        playerNameInputSection
                    }
                }
            }, footer: {
                HStack {
                    Button(
                        "Cancel"
                    ) {
                        authService.isLoading = false
                        onCancel()
                    }
                    
                    Spacer()
                    
                    if selectedAuthType == .premium {
                        // Show different buttons based on authentication status
                        switch authService.authState {
                        case .notAuthenticated:
                            Button("Start Login") {
                                Task {
                                    await authService.startAuthentication()
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            
                        case .authenticated(let profile):
                            
                            Button("Add") {
                                onLogin(profile)
                            }
                            .keyboardShortcut(.defaultAction)
                            
                        case .error:
                            Button("Retry") {
                                Task {
                                    await authService.startAuthentication()
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            
                        default:
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Button(
                            "Purchase Minecraft"
                        ) {
                            openURL(URLConfig.Store.minecraftPurchase)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        
                        Button(
                            "Create account"
                        ) {
                            authService.isLoading = false
                            onAdd()
                        }
                        .disabled(!isPlayerNameValid)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        )
        .task {
            // Check mark
            await checkPremiumAccountFlag()
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
    }
    
    // MARK: - check logic
    
    /// Check if you can add an offline account
    private func canAddOfflineAccount() -> Bool {
        // Check the mark: If a genuine account has been added (the mark exists), you can add an offline account
        let flagManager = PremiumAccountFlagManager.shared
        if flagManager.hasAddedPremiumAccount() {
            return true
        }
        
        // If there is no tag, you need to check the IP geolocation
        // If it is a foreign IP, adding an offline account is not allowed
        // If it is a domestic IP (or the check fails), offline accounts are allowed to be added
        return !isForeignIP
    }
    
    /// Check genuine account mark
    private func checkPremiumAccountFlag() async {
        // Check mark
        let flagManager = PremiumAccountFlagManager.shared
        let hasFlag = flagManager.hasAddedPremiumAccount()
        // If there is no tag, check the IP geolocation simultaneously
        if !hasFlag {
            // The loading status has been displayed and will continue to be displayed until the IP check is completed
            let locationService = IPLocationService.shared
            let foreign = await locationService.isForeignIP()
            
            await MainActor.run {
                isForeignIP = foreign
                isCheckingFlag = false
                
                // selectedAuthType falls among the available options
                if !availableAuthTypes.contains(selectedAuthType) {
                    selectedAuthType = .premium
                }
            }
        } else {
            // If marked, allow adding offline accounts
            await MainActor.run {
                isCheckingFlag = false
            }
        }
    }
    
    /// Get a list of available authentication types
    private var availableAuthTypes: [AccountAuthType] {
        // If offline accounts can be added, show all options
        if canAddOfflineAccount() {
            return AccountAuthType.allCases
        }
        
        // If it is a foreign IP and there is no genuine account in the list, only the genuine option will be displayed
        return [.premium]
    }
    
    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // Clean up player names
        playerName = ""
        isPlayerNameValid = false
        // Clear authentication status
        authenticatedProfile = nil
        isPremium = false
        // Reset authentication service status
        authService.isLoading = false
        // Reset focus state
        isTextFieldFocused = false
        showErrorPopover = false
        // Reset authentication type
        selectedAuthType = .premium
        // Reset tag check status
        isCheckingFlag = true
        // Reset IP check results
        isForeignIP = false
    }
    
    // Description area
    private var playerInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Offline Account Information")
                .font(.headline) .padding(.bottom, 4)
            Text("• Offline accounts do not require network verification and can play games without an internet connection")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("• The player name length is 1-16 characters, and can only contain letters, numbers, and underscores.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("• Offline accounts cannot be used on the official server.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("• Each player name can only create one offline account")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // input area
    private var playerNameInputSection: some View {
        VStack(alignment: .leading) {
            Text("Player Name")
                .font(.headline.bold())
            TextField(
                "Enter player name to be used as your display name in the game",
                text: $playerName
            )
            .textFieldStyle(.roundedBorder)
            .focused($isTextFieldFocused)
            .focusEffectDisabled()
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(borderColor, lineWidth: 2)
            )
            .popover(isPresented: $showErrorPopover, arrowEdge: .trailing) {
                if let errorMessage = playerNameError {
                    Text(errorMessage)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            .onChange(of: playerName) { _, newValue in
                checkPlayerName(newValue)
            }
        }
    }
    
    // Determine border color based on input state and focus state
    private var borderColor: Color {
        if isTextFieldFocused {
            .blue
        } else {
            .clear
        }
    }
    
    // Get error information (only when illegal, excluding empty string)
    private var playerNameError: String? {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        if playerListViewModel.playerExists(name: trimmedName) {
            return String(localized: "Player name already exists")
        }
        // Other verification rules can be added
        return nil
    }
    
    private func checkPlayerName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Set status based on playerNameError and whether it is empty to avoid repeated checks
        let hasError = playerNameError != nil
        isPlayerNameValid = !trimmedName.isEmpty && !hasError
        showErrorPopover = hasError
    }
}

// Assuming AccountAuthType is defined as:
enum AccountAuthType: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    
    case offline, premium
    
    var displayName: String {
        switch self {
        case .premium: String(localized: "Microsoft")
        default: String(localized: "Offline")
        }
    }
}

// 1. Extend a symbol configuration to AccountAuthType
extension AccountAuthType {
    var symbol: (name: String, mode: SymbolRenderingMode) {
        switch self {
        case .premium:
            return ("person.crop.circle.badge.plus", .multicolor)
        default:
            return ("person.crop.circle.badge.minus", .multicolor)
        }
    }
}

import SwiftUI

/// AI chat message list view
struct AIChatMessageListView: View {
    @ObservedObject var chatState: ChatState
    let currentPlayer: Player?
    let cachedAIAvatar: AnyView?
    let cachedUserAvatar: AnyView?
    let aiAvatarURL: String
    
    // Status used for anti-shaking and avoiding loop updates
    @State private var lastContentLength: Int = 0
    @State private var scrollTask: Task<Void, Never>?
    @State private var periodicScrollTask: Task<Void, Never>?
    
    private enum Constants {
        static let avatarSize: CGFloat = 32
        static let messageSpacing: CGFloat = 16
        static let messageVerticalPadding: CGFloat = 2
        static let scrollDelay: TimeInterval = 0.1
        static let scrollAnimationDuration: TimeInterval = 0.3
        static let scrollThrottleInterval: TimeInterval = 0.2 // Anti-shake interval
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    if chatState.messages.isEmpty {
                        // Show greeting message when empty message
                        VStack {
                            Spacer()
                            welcomeView
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            messageListView
                            
                            // Show "Thinking" only if sending is in progress and the last AI message was empty
                            if chatState.isSending,
                               let lastMessage = chatState.messages.last,
                               lastMessage.role == .assistant,
                               lastMessage.content.isEmpty {
                                loadingIndicatorView
                            }
                        }
                        .padding()
                    }
                }
                // Scroll to the bottom: Optimization - Use anti-shake mechanism to avoid loops caused by frequent updates
                .onChange(of: chatState.messages.count) { _, _ in
                    // Scroll on new messages
                    if chatState.messages.last != nil {
                        scheduleScroll(proxy: proxy)
                    }
                }
                .onChange(of: chatState.messages.last?.id) { _, _ in
                    // When the ID of the last message changes (new message), reset content length tracking and scroll
                    if let lastMessage = chatState.messages.last {
                        lastContentLength = lastMessage.content.count
                        scheduleScroll(proxy: proxy)
                    }
                }
                .onChange(of: chatState.isSending) { oldValue, newValue in
                    if !oldValue && newValue {
                        // When sending starts, start a periodic rolling check
                        startPeriodicScrollCheck(proxy: proxy)
                    } else if oldValue && !newValue {
                        // When sending is complete, stop the periodic scroll check and scroll to the bottom
                        stopPeriodicScrollCheck()
                        scheduleScroll(proxy: proxy)
                    }
                }
                .onAppear {
                    // When the view appears, initiate a periodic scroll check if sending
                    if chatState.isSending {
                        startPeriodicScrollCheck(proxy: proxy)
                    }
                }
                .onDisappear {
                    // Stop all scrolling tasks when the view disappears
                    stopPeriodicScrollCheck()
                    scrollTask?.cancel()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var welcomeView: some View {
        VStack(spacing: 16) {
            if let player = currentPlayer {
                Text("Hello, \(player.name)!")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.primary)
            }
            
            Text("How can I help you today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private var messageListView: some View {
        ForEach(chatState.messages) { message in
            // Skip empty AI messages being sent (loading indicator will be shown)
            if !(chatState.isSending && message.role == .assistant && message.content.isEmpty) {
                MessageBubble(
                    message: message,
                    currentPlayer: currentPlayer,
                    cachedAIAvatar: cachedAIAvatar,
                    cachedUserAvatar: cachedUserAvatar,
                    aiAvatarURL: aiAvatarURL
                )
                .id(message.id)
            }
        }
    }
    
    private var loadingIndicatorView: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.messageSpacing) {
            // Using cached avatar view
            if let cachedAvatar = cachedAIAvatar {
                cachedAvatar
            } else {
                AIAvatarView(size: Constants.avatarSize, url: aiAvatarURL)
            }
            
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .controlSize(.small)
                
                Text("Thinking...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 40)
        }
        .padding(.vertical, Constants.messageVerticalPadding)
    }
    
    // MARK: - Methods
    
    /// Scheduling scroll to bottom (with anti-shake)
    private func scheduleScroll(proxy: ScrollViewProxy) {
        // Cancel previous task
        scrollTask?.cancel()
        
        // Create a new anti-shake task
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.scrollThrottleInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy: proxy)
        }
    }
    
    /// Start periodic rolling checks (for streaming updates)
    private func startPeriodicScrollCheck(proxy: ScrollViewProxy) {
        stopPeriodicScrollCheck()
        
        periodicScrollTask = Task { @MainActor in
            while !Task.isCancelled && chatState.isSending {
                // Check if the content is updated
                if let lastMessage = chatState.messages.last,
                   lastMessage.content.count > lastContentLength {
                    lastContentLength = lastMessage.content.count
                    scrollToBottom(proxy: proxy)
                }
                
                // Check every 0.3 seconds
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
    
    /// Stop periodic rolling checks
    private func stopPeriodicScrollCheck() {
        periodicScrollTask?.cancel()
        periodicScrollTask = nil
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.scrollDelay * 1_000_000_000))
            guard let lastMessage = chatState.messages.last else { return }
            withAnimation(.easeOut(duration: Constants.scrollAnimationDuration)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

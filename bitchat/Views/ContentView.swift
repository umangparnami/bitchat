//
// ContentView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Supporting Types

//

//

// MARK: - Main Content View

struct ContentView: View {
    // MARK: - Properties
    
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var bookmarks = GeohashBookmarksStore.shared
    @ObservedObject private var notesCounter = LocationNotesCounter.shared
    @State private var messageText = ""
    @State private var textFieldSelection: NSRange? = nil
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showPeerList = false
    @State private var showSidebar = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var showAppInfo = false
    @State private var showCommandSuggestions = false
    @State private var commandSuggestions: [String] = []
    @State private var backSwipeOffset: CGFloat = 0
    @State private var showPrivateChat = false
    @State private var showMessageActions = false
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: String?
    @FocusState private var isNicknameFieldFocused: Bool
    @State private var isAtBottomPublic: Bool = true
    @State private var isAtBottomPrivate: Bool = true
    @State private var lastScrollTime: Date = .distantPast
    @State private var scrollThrottleTimer: Timer?
    @State private var autocompleteDebounceTimer: Timer?
    @State private var showLocationChannelsSheet = false
    @State private var showVerifySheet = false
    @State private var expandedMessageIDs: Set<String> = []
    @State private var showLocationNotes = false
    @State private var notesGeohash: String? = nil
    @State private var sheetNotesCount: Int = 0
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerIconSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerCountFontSize: CGFloat = 12
    // Timer-based refresh removed; use LocationChannelManager live updates instead
    // Window sizes for rendering (infinite scroll up)
    @State private var windowCountPublic: Int = 300
    @State private var windowCountPrivate: [String: Int] = [:]
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }

    private var headerLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base layer - Main public chat (always visible)
                mainChatView
                    .onAppear { viewModel.currentColorScheme = colorScheme }
                    .onChange(of: colorScheme) { newValue in
                        viewModel.currentColorScheme = newValue
                    }
                
                // Private chat slide-over
                if viewModel.selectedPrivateChatPeer != nil {
                    privateChatView
                        .frame(width: geometry.size.width)
                        .background(backgroundColor)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                        .offset(x: showPrivateChat ? -1 : max(0, geometry.size.width))
                        .offset(x: backSwipeOffset.isNaN ? 0 : backSwipeOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.width > 0 && !value.translation.width.isNaN {
                                        let maxWidth = max(0, geometry.size.width)
                                        backSwipeOffset = min(value.translation.width, maxWidth.isNaN ? 0 : maxWidth)
                                    }
                                }
                                .onEnded { value in
                                    let translation = value.translation.width.isNaN ? 0 : value.translation.width
                                    let velocity = value.velocity.width.isNaN ? 0 : value.velocity.width
                                    if translation > TransportConfig.uiBackSwipeTranslationLarge || (translation > TransportConfig.uiBackSwipeTranslationSmall && velocity > TransportConfig.uiBackSwipeVelocityThreshold) {
                                        withAnimation(.easeOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                                            showPrivateChat = false
                                            backSwipeOffset = 0
                                            viewModel.endPrivateChat()
                                        }
                                    } else {
                                        withAnimation(.easeOut(duration: TransportConfig.uiAnimationShortSeconds)) {
                                            backSwipeOffset = 0
                                        }
                                    }
                                }
                        )
                }
                
                // Sidebar overlay
                HStack(spacing: 0) {
                    // Tap to dismiss area
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                                showSidebar = false
                                sidebarDragOffset = 0
                            }
                        }
                    
                    // Only render sidebar content when it's visible or animating
                    if showSidebar || sidebarDragOffset != 0 {
                        sidebarView
                            #if os(macOS)
                            .frame(width: min(300, max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.4))
                            #else
                            .frame(width: max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.7)
                            #endif
                            .transition(.move(edge: .trailing))
                    } else {
                        // Empty placeholder when hidden
                        Color.clear
                            #if os(macOS)
                            .frame(width: min(300, max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.4))
                            #else
                            .frame(width: max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.7)
                            #endif
                    }
                }
                .offset(x: {
                    let dragOffset = sidebarDragOffset.isNaN ? 0 : sidebarDragOffset
                    let width = geometry.size.width.isNaN ? 0 : max(0, geometry.size.width)
                    return showSidebar ? -dragOffset : width - dragOffset
                }())
                .animation(.easeInOut(duration: TransportConfig.uiAnimationSidebarSeconds), value: showSidebar)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onChange(of: viewModel.selectedPrivateChatPeer) { newValue in
            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                showPrivateChat = newValue != nil
            }
        }
        .sheet(isPresented: $showAppInfo) {
            AppInfoView()
                .onAppear { viewModel.isAppInfoPresented = true }
                .onDisappear { viewModel.isAppInfoPresented = false }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingFingerprintFor != nil },
            set: { _ in viewModel.showingFingerprintFor = nil }
        )) {
            if let peerID = viewModel.showingFingerprintFor {
                FingerprintView(viewModel: viewModel, peerID: peerID)
            }
        }
        .confirmationDialog(
            selectedMessageSender.map { "@\($0)" } ?? L10n.string(
                "content.actions.title",
                comment: "Fallback title for the message action sheet"
            ),
            isPresented: $showMessageActions,
            titleVisibility: .visible
        ) {
            Button("content.actions.mention") {
                if let sender = selectedMessageSender {
                    // Pre-fill the input with an @mention and focus the field
                    messageText = "@\(sender) "
                    isTextFieldFocused = true
                }
            }

            Button("content.actions.direct_message") {
                if let peerID = selectedMessageSenderID {
                    if peerID.hasPrefix("nostr:") {
                        if let full = viewModel.fullNostrHex(forSenderPeerID: peerID) {
                            viewModel.startGeohashDM(withPubkeyHex: full)
                        }
                    } else {
                        viewModel.startPrivateChat(with: peerID)
                    }
                    withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                        showSidebar = false
                        sidebarDragOffset = 0
                    }
                }
            }

            Button("content.actions.hug") {
                if let sender = selectedMessageSender {
                    viewModel.sendMessage("/hug @\(sender)")
                }
            }

            Button("content.actions.slap") {
                if let sender = selectedMessageSender {
                    viewModel.sendMessage("/slap @\(sender)")
                }
            }

            Button("content.actions.block", role: .destructive) {
                // Prefer direct geohash block when we have a Nostr sender ID
                if let peerID = selectedMessageSenderID, peerID.hasPrefix("nostr:"),
                   let full = viewModel.fullNostrHex(forSenderPeerID: peerID),
                   let sender = selectedMessageSender {
                    viewModel.blockGeohashUser(pubkeyHexLowercased: full, displayName: sender)
                } else if let sender = selectedMessageSender {
                    viewModel.sendMessage("/block \(sender)")
                }
            }

            Button("common.cancel", role: .cancel) {}
        }
        .alert("content.alert.bluetooth_required.title", isPresented: $viewModel.showBluetoothAlert) {
            Button("content.alert.bluetooth_required.settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(viewModel.bluetoothAlertMessage)
        }
        .onDisappear {
            // Clean up timers
            scrollThrottleTimer?.invalidate()
            autocompleteDebounceTimer?.invalidate()
        }
    }
    
    // MARK: - Message List View
    
    private func messagesView(privatePeer: String?, isAtBottom: Binding<Bool>) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Extract messages based on context (private or public chat)
                    let messages: [BitchatMessage] = {
                        if let privatePeer = privatePeer {
                            let msgs = viewModel.getPrivateChatMessages(for: privatePeer)
                            return msgs
                        } else {
                            return viewModel.messages
                        }
                    }()
                    
                    // Implement windowing with adjustable window count per chat
                    let currentWindowCount: Int = {
                        if let peer = privatePeer { return windowCountPrivate[peer] ?? TransportConfig.uiWindowInitialCountPrivate }
                        return windowCountPublic
                    }()
                    let windowedMessages = messages.suffix(currentWindowCount)

                    // Build stable UI IDs with a context key to avoid ID collisions when switching channels
                    let contextKey: String = {
                        if let peer = privatePeer { return "dm:\(peer)" }
                        switch locationManager.selectedChannel {
                        case .mesh: return "mesh"
                        case .location(let ch): return "geo:\(ch.geohash)"
                        }
                    }()
                    let items = windowedMessages.map { (uiID: "\(contextKey)|\($0.id)", message: $0) }
                    // Filter out empty/whitespace-only messages to avoid blank rows
                    let filteredItems = items.filter { !$0.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                    ForEach(filteredItems, id: \.uiID) { item in
                        let message = item.message
                        VStack(alignment: .leading, spacing: 0) {
                            // Check if current user is mentioned
                            
                            if message.sender == "system" {
                                // System messages
                                Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                // Regular messages with natural text wrapping
                                VStack(alignment: .leading, spacing: 0) {
                                    // Precompute heavy token scans once per row
                                    let cashuTokens = message.content.extractCashuTokens()
                                    let lightningLinks = message.content.extractLightningLinks()
                                    HStack(alignment: .top, spacing: 0) {
                                        let isLong = (message.content.count > TransportConfig.uiLongMessageLengthThreshold || message.content.hasVeryLongToken(threshold: TransportConfig.uiVeryLongTokenThreshold)) && cashuTokens.isEmpty
                                        let isExpanded = expandedMessageIDs.contains(message.id)
                                        Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineLimit(isLong && !isExpanded ? TransportConfig.uiLongMessageLineLimit : nil)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // Delivery status indicator for private messages
                                        if message.isPrivate && message.sender == viewModel.nickname,
                                           let status = message.deliveryStatus {
                                            DeliveryStatusView(status: status, colorScheme: colorScheme)
                                                .padding(.leading, 4)
                                        }
                                    }
                                    
                                    // Expand/Collapse for very long messages
                                    if (message.content.count > TransportConfig.uiLongMessageLengthThreshold || message.content.hasVeryLongToken(threshold: TransportConfig.uiVeryLongTokenThreshold)) && cashuTokens.isEmpty {
                                        let isExpanded = expandedMessageIDs.contains(message.id)
                                        let labelKey = isExpanded ? LocalizedStringKey("content.message.show_less") : LocalizedStringKey("content.message.show_more")
                                        Button(labelKey) {
                                            if isExpanded { expandedMessageIDs.remove(message.id) }
                                            else { expandedMessageIDs.insert(message.id) }
                                        }
                                        .font(.bitchatSystem(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color.blue)
                                        .padding(.top, 4)
                                    }

                                    // Render payment chips (Lightning / Cashu) with rounded background
                                    if !lightningLinks.isEmpty || !cashuTokens.isEmpty {
                                        HStack(spacing: 8) {
                                            ForEach(Array(lightningLinks.prefix(3)).indices, id: \.self) { i in
                                                let link = lightningLinks[i]
                                                PaymentChipView(
                                                    emoji: "⚡",
                                                    label: L10n.string(
                                                        "content.payment.lightning",
                                                        comment: "Label for Lightning payment chip"
                                                    ),
                                                    colorScheme: colorScheme
                                                ) {
                                                    #if os(iOS)
                                                    if let url = URL(string: link) { UIApplication.shared.open(url) }
                                                    #else
                                                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                                                    #endif
                                                }
                                            }
                                            ForEach(Array(cashuTokens.prefix(3)).indices, id: \.self) { i in
                                                let token = cashuTokens[i]
                                                let enc = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? token
                                                let urlStr = "cashu:\(enc)"
                                                PaymentChipView(
                                                    emoji: "🥜",
                                                    label: L10n.string(
                                                        "content.payment.cashu",
                                                        comment: "Label for Cashu payment chip"
                                                    ),
                                                    colorScheme: colorScheme
                                                ) {
                                                    #if os(iOS)
                                                    if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
                                                    #else
                                                    if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                                                    #endif
                                                }
                                            }
                                        }
                                        .padding(.top, 6)
                                        .padding(.leading, 2)
                                    }
                                }
                            }
                        }
                        .id(item.uiID)
                        .onAppear {
                            // Track if last item is visible to enable auto-scroll only when near bottom
                            if message.id == windowedMessages.last?.id {
                                isAtBottom.wrappedValue = true
                            }
                            // Infinite scroll up: when top row appears, increase window and preserve anchor
                            if message.id == windowedMessages.first?.id, messages.count > windowedMessages.count {
                                let step = TransportConfig.uiWindowStepCount
                                let contextKey: String = {
                                    if let peer = privatePeer { return "dm:\(peer)" }
                                    switch locationManager.selectedChannel {
                                    case .mesh: return "mesh"
                                    case .location(let ch): return "geo:\(ch.geohash)"
                                    }
                                }()
                                let preserveID = "\(contextKey)|\(message.id)"
                                if let peer = privatePeer {
                                    let current = windowCountPrivate[peer] ?? TransportConfig.uiWindowInitialCountPrivate
                                    let newCount = min(messages.count, current + step)
                                    if newCount != current {
                                        windowCountPrivate[peer] = newCount
                                        DispatchQueue.main.async {
                                            proxy.scrollTo(preserveID, anchor: .top)
                                        }
                                    }
                                } else {
                                    let current = windowCountPublic
                                    let newCount = min(messages.count, current + step)
                                    if newCount != current {
                                        windowCountPublic = newCount
                                        DispatchQueue.main.async {
                                            proxy.scrollTo(preserveID, anchor: .top)
                                        }
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            if message.id == windowedMessages.last?.id {
                                isAtBottom.wrappedValue = false
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap on message body: insert @mention for this sender
                            if message.sender != "system" {
                                let name = message.sender
                                messageText = "@\(name) "
                                isTextFieldFocused = true
                            }
                        }
                        .contextMenu {
                            Button("content.message.copy") {
                                #if os(iOS)
                                UIPasteboard.general.string = message.content
                                #else
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(message.content, forType: .string)
                                #endif
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .transaction { tx in if viewModel.isBatchingPublic { tx.disablesAnimations = true } }
                .padding(.vertical, 4)
            }
            .background(backgroundColor)
            .onOpenURL { url in
                guard url.scheme == "bitchat", url.host == "user" else { return }
                let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let peerID = id.removingPercentEncoding ?? id
                selectedMessageSenderID = peerID
                // Derive a stable display name from the peerID instead of peeking at the last message,
                // which may be a transformed system action (sender == "system").
                if peerID.hasPrefix("nostr") {
                    // For geohash senders, resolve display name via mapping (works for "nostr:" and "nostr_" keys)
                    selectedMessageSender = viewModel.geohashDisplayName(for: peerID)
                } else {
                    // Mesh sender: use current mesh nickname if available; otherwise fall back to last non-system message
                    if let name = viewModel.meshService.peerNickname(peerID: peerID) {
                        selectedMessageSender = name
                    } else {
                        selectedMessageSender = viewModel.messages.last(where: { $0.senderPeerID == peerID && $0.sender != "system" })?.sender
                    }
                }
                if viewModel.isSelfSender(peerID: selectedMessageSenderID, displayName: selectedMessageSender) {
                    selectedMessageSender = nil
                    selectedMessageSenderID = nil
                } else {
                    showMessageActions = true
                }
            }
            .onOpenURL { url in
                guard url.scheme == "bitchat", url.host == "geohash" else { return }
                let gh = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
                guard (2...12).contains(gh.count), gh.allSatisfy({ allowed.contains($0) }) else { return }
                func levelForLength(_ len: Int) -> GeohashChannelLevel {
                    switch len {
                        case 0...2: return .region
                        case 3...4: return .province
                        case 5: return .city
                        case 6: return .neighborhood
                    case 7: return .block
                    default: return .block
                        }
                    }
                let level = levelForLength(gh.count)
                let ch = GeohashChannel(level: level, geohash: gh)
                // Do not mark teleported when opening a geohash that is in our regional set.
                // If availableChannels is empty (e.g., cold start), defer marking and let
                // LocationChannelManager compute teleported based on actual location.
                let inRegional = LocationChannelManager.shared.availableChannels.contains { $0.geohash == gh }
                if !inRegional && !LocationChannelManager.shared.availableChannels.isEmpty {
                    LocationChannelManager.shared.markTeleported(for: gh, true)
                }
                LocationChannelManager.shared.select(ChannelID.location(ch))
            }
            .onTapGesture(count: 3) {
                // Triple-tap to clear current chat
                viewModel.sendMessage("/clear")
            }
            .onAppear {
                // Force scroll to bottom when opening a chat view
                let targetID: String? = {
                    if let peer = privatePeer,
                       let last = viewModel.getPrivateChatMessages(for: peer).suffix(300).last?.id {
                        return "dm:\(peer)|\(last)"
                    }
                    let contextKey: String = {
                        switch locationManager.selectedChannel {
                        case .mesh: return "mesh"
                        case .location(let ch): return "geo:\(ch.geohash)"
                        }
                    }()
                    if let last = viewModel.messages.suffix(300).last?.id { return "\(contextKey)|\(last)" }
                    return nil
                }()
                isAtBottom.wrappedValue = true
                DispatchQueue.main.async {
                    if let target = targetID { proxy.scrollTo(target, anchor: .bottom) }
                }
                // Second pass after a brief delay to handle late layout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let targetID2: String? = {
                        if let peer = privatePeer,
                           let last = viewModel.getPrivateChatMessages(for: peer).suffix(300).last?.id {
                            return "dm:\(peer)|\(last)"
                        }
                        let contextKey: String = {
                            switch locationManager.selectedChannel {
                            case .mesh: return "mesh"
                            case .location(let ch): return "geo:\(ch.geohash)"
                            }
                        }()
                        if let last = viewModel.messages.suffix(300).last?.id { return "\(contextKey)|\(last)" }
                        return nil
                    }()
                    if let t2 = targetID2 { proxy.scrollTo(t2, anchor: .bottom) }
                }
            }
            .onChange(of: privatePeer) { _ in
                // When switching to a different private chat, jump to bottom
                let targetID: String? = {
                    if let peer = privatePeer,
                       let last = viewModel.getPrivateChatMessages(for: peer).suffix(300).last?.id {
                        return "dm:\(peer)|\(last)"
                    }
                    let contextKey: String = {
                        switch locationManager.selectedChannel {
                        case .mesh: return "mesh"
                        case .location(let ch): return "geo:\(ch.geohash)"
                        }
                    }()
                    if let last = viewModel.messages.suffix(300).last?.id { return "\(contextKey)|\(last)" }
                    return nil
                }()
                isAtBottom.wrappedValue = true
                DispatchQueue.main.async {
                    if let target = targetID { proxy.scrollTo(target, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.messages.count) { _ in
                if privatePeer == nil && !viewModel.messages.isEmpty {
                    // If the newest message is from me, always scroll to bottom
                    let lastMsg = viewModel.messages.last!
                    let isFromSelf = (lastMsg.sender == viewModel.nickname) || lastMsg.sender.hasPrefix(viewModel.nickname + "#")
                    if !isFromSelf {
                        // Only autoscroll when user is at/near bottom
                        guard isAtBottom.wrappedValue else { return }
                    } else {
                        // Ensure we consider ourselves at bottom for subsequent messages
                        isAtBottom.wrappedValue = true
                    }
                    // Throttle scroll animations to prevent excessive UI updates
                    let now = Date()
                    if now.timeIntervalSince(lastScrollTime) > TransportConfig.uiScrollThrottleSeconds {
                        // Immediate scroll if enough time has passed
                        lastScrollTime = now
                        let contextKey: String = {
                            switch locationManager.selectedChannel {
                            case .mesh: return "mesh"
                            case .location(let ch): return "geo:\(ch.geohash)"
                            }
                        }()
                        let count = windowCountPublic
                        let target = viewModel.messages.suffix(count).last.map { "\(contextKey)|\($0.id)" }
                        DispatchQueue.main.async {
                            if let target = target { proxy.scrollTo(target, anchor: .bottom) }
                        }
                    } else {
                        // Schedule a delayed scroll
                        scrollThrottleTimer?.invalidate()
                        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: TransportConfig.uiScrollThrottleSeconds, repeats: false) { _ in
                            lastScrollTime = Date()
                        let contextKey: String = {
                            switch locationManager.selectedChannel {
                            case .mesh: return "mesh"
                            case .location(let ch): return "geo:\(ch.geohash)"
                            }
                        }()
                            let count = windowCountPublic
                            let target = viewModel.messages.suffix(count).last.map { "\(contextKey)|\($0.id)" }
                            DispatchQueue.main.async {
                                if let target = target { proxy.scrollTo(target, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .onChange(of: viewModel.privateChats) { _ in
                if let peerID = privatePeer,
                   let messages = viewModel.privateChats[peerID],
                   !messages.isEmpty {
                    // If the newest private message is from me, always scroll
                    let lastMsg = messages.last!
                    let isFromSelf = (lastMsg.sender == viewModel.nickname) || lastMsg.sender.hasPrefix(viewModel.nickname + "#")
                    if !isFromSelf {
                        // Only autoscroll when user is at/near bottom
                        guard isAtBottom.wrappedValue else { return }
                    } else {
                        isAtBottom.wrappedValue = true
                    }
                    // Same throttling for private chats
                    let now = Date()
                    if now.timeIntervalSince(lastScrollTime) > TransportConfig.uiScrollThrottleSeconds {
                        lastScrollTime = now
                        let contextKey = "dm:\(peerID)"
                        let count = windowCountPrivate[peerID] ?? 300
                        let target = messages.suffix(count).last.map { "\(contextKey)|\($0.id)" }
                        DispatchQueue.main.async {
                            if let target = target { proxy.scrollTo(target, anchor: .bottom) }
                        }
                    } else {
                        scrollThrottleTimer?.invalidate()
                        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: TransportConfig.uiScrollThrottleSeconds, repeats: false) { _ in
                            lastScrollTime = Date()
                            let contextKey = "dm:\(peerID)"
                            let count = windowCountPrivate[peerID] ?? 300
                            let target = messages.suffix(count).last.map { "\(contextKey)|\($0.id)" }
                            DispatchQueue.main.async {
                                if let target = target { proxy.scrollTo(target, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .onChange(of: locationManager.selectedChannel) { newChannel in
                // When switching to a new geohash channel, scroll to the bottom
                guard privatePeer == nil else { return }
                switch newChannel {
                case .mesh:
                    break
                case .location(let ch):
                    // Reset window size
                    windowCountPublic = TransportConfig.uiWindowInitialCountPublic
                    let contextKey = "geo:\(ch.geohash)"
                    let last = viewModel.messages.suffix(windowCountPublic).last?.id
                    let target = last.map { "\(contextKey)|\($0)" }
                    isAtBottom.wrappedValue = true
                    DispatchQueue.main.async {
                        if let target = target { proxy.scrollTo(target, anchor: .bottom) }
                    }
                }
            }
            .onAppear {
                // Also check when view appears
                if let peerID = privatePeer {
                    // Try multiple times to ensure read receipts are sent
                    viewModel.markPrivateMessagesAsRead(from: peerID)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + TransportConfig.uiReadReceiptRetryShortSeconds) {
                        viewModel.markPrivateMessagesAsRead(from: peerID)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + TransportConfig.uiReadReceiptRetryLongSeconds) {
                        viewModel.markPrivateMessagesAsRead(from: peerID)
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            // Intercept custom cashu: links created in attributed text
            if let scheme = url.scheme?.lowercased(), scheme == "cashu" || scheme == "lightning" {
                #if os(iOS)
                UIApplication.shared.open(url)
                return .handled
                #else
                // On non-iOS platforms, let the system handle or ignore
                return .systemAction
                #endif
            }
            return .systemAction
        })
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        VStack(spacing: 0) {
            // @mentions autocomplete
            if viewModel.showAutocomplete && !viewModel.autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.autocompleteSuggestions.prefix(4)), id: \.self) { suggestion in
                        Button(action: {
                            _ = viewModel.completeNickname(suggestion, in: &messageText)
                        }) {
                            HStack {
                                Text(suggestion)
                                    .font(.bitchatSystem(size: 11, design: .monospaced))
                                    .foregroundColor(textColor)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(Color.gray.opacity(0.1))
                    }
                }
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
            }
            
            // Command suggestions
            if showCommandSuggestions && !commandSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Define commands with aliases and syntax
                    let baseInfo: [(commands: [String], syntax: String?, description: String)] = [
                        (["/block"], "[nickname]", "block or list blocked peers"),
                        (["/clear"], nil, "clear chat messages"),
                        (["/hug"], "<nickname>", "send someone a warm hug"),
                        (["/m", "/msg"], "<nickname> [message]", "send private message"),
                        (["/slap"], "<nickname>", "slap someone with a trout"),
                        (["/unblock"], "<nickname>", "unblock a peer"),
                        (["/w"], nil, "see who's online")
                    ]
                    let isGeoPublic: Bool = { if case .location = locationManager.selectedChannel { return true }; return false }()
                    let isGeoDM: Bool = (viewModel.selectedPrivateChatPeer?.hasPrefix("nostr_") == true)
                    let favInfo: [(commands: [String], syntax: String?, description: String)] = [
                        (["/fav"], "<nickname>", "add to favorites"),
                        (["/unfav"], "<nickname>", "remove from favorites")
                    ]
                    let commandInfo = baseInfo + ((isGeoPublic || isGeoDM) ? [] : favInfo)
                    
                    // Build the display
                    let allCommands = commandInfo
                    
                    // Show matching commands
                    ForEach(commandSuggestions, id: \.self) { command in
                        // Find the command info for this suggestion
                        if let info = allCommands.first(where: { $0.commands.contains(command) }) {
                            Button(action: {
                                // Replace current text with selected command
                                messageText = command + " "
                                showCommandSuggestions = false
                                commandSuggestions = []
                            }) {
                                HStack {
                                    // Show all aliases together
                                    Text(info.commands.joined(separator: ", "))
                                        .font(.bitchatSystem(size: 11, design: .monospaced))
                                        .foregroundColor(textColor)
                                        .fontWeight(.medium)
                                    
                                    // Show syntax if any
                                    if let syntax = info.syntax {
                                        Text(syntax)
                                            .font(.bitchatSystem(size: 10, design: .monospaced))
                                            .foregroundColor(secondaryTextColor.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    // Show description
                                    Text(info.description)
                                        .font(.bitchatSystem(size: 10, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .background(Color.gray.opacity(0.1))
                        }
                    }
                }
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
            }
            
            HStack(alignment: .center, spacing: 4) {
        TextField("content.input.message_placeholder", text: $messageText)
                .textFieldStyle(.plain)
                .font(.bitchatSystem(size: 14, design: .monospaced))
                .foregroundColor(textColor)
                .focused($isTextFieldFocused)
                .padding(.leading, 12)
                // iOS keyboard autocomplete and capitalization enabled by default
                .onChange(of: messageText) { newValue in
                    // Cancel previous debounce timer
                    autocompleteDebounceTimer?.invalidate()
                    
                    // Debounce autocomplete updates to reduce calls during rapid typing
                    autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                        // Get cursor position (approximate - end of text for now)
                        let cursorPosition = newValue.count
                        viewModel.updateAutocomplete(for: newValue, cursorPosition: cursorPosition)
                    }
                    
                    // Check for command autocomplete (instant, no debounce needed)
                    if newValue.hasPrefix("/") && newValue.count >= 1 {
                        // Build context-aware command list
                        let isGeoPublic: Bool = {
                            if case .location = locationManager.selectedChannel { return true }
                            return false
                        }()
                        let isGeoDM: Bool = (viewModel.selectedPrivateChatPeer?.hasPrefix("nostr_") == true)
                        var commandDescriptions = [
                            ("/block", L10n.string("content.commands.block", comment: "Description for /block command")),
                            ("/clear", L10n.string("content.commands.clear", comment: "Description for /clear command")),
                            ("/hug", L10n.string("content.commands.hug", comment: "Description for /hug command")),
                            ("/m", L10n.string("content.commands.message", comment: "Description for /m command")),
                            ("/slap", L10n.string("content.commands.slap", comment: "Description for /slap command")),
                            ("/unblock", L10n.string("content.commands.unblock", comment: "Description for /unblock command")),
                            ("/w", L10n.string("content.commands.who", comment: "Description for /w command"))
                        ]
                        // Only show favorites commands when not in geohash context
                        if !(isGeoPublic || isGeoDM) {
                            commandDescriptions.append(("/fav", L10n.string("content.commands.favorite", comment: "Description for /fav command")))
                            commandDescriptions.append(("/unfav", L10n.string("content.commands.unfavorite", comment: "Description for /unfav command")))
                        }
                        
                        let input = newValue.lowercased()
                        
                        // Map of aliases to primary commands
                        let aliases: [String: String] = [
                            "/join": "/j",
                            "/msg": "/m"
                        ]
                        
                        // Filter commands, but convert aliases to primary
                        commandSuggestions = commandDescriptions
                            .filter { $0.0.starts(with: input) }
                            .map { $0.0 }
                        
                        // Also check if input matches an alias
                        for (alias, primary) in aliases {
                            if alias.starts(with: input) && !commandSuggestions.contains(primary) {
                                if commandDescriptions.contains(where: { $0.0 == primary }) {
                                    commandSuggestions.append(primary)
                                }
                            }
                        }
                        
                        // Remove duplicates and sort
                        commandSuggestions = Array(Set(commandSuggestions)).sorted()
                        showCommandSuggestions = !commandSuggestions.isEmpty
                    } else {
                        showCommandSuggestions = false
                        commandSuggestions = []
                    }
                }
                .onSubmit {
                    sendMessage()
                }
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.bitchatSystem(size: 20))
                    .foregroundColor(messageText.isEmpty ? Color.gray :
                                            viewModel.selectedPrivateChatPeer != nil
                                             ? Color.orange : textColor)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel(
                L10n.string(
                    "content.accessibility.send_message",
                    comment: "Accessibility label for the send message button"
                )
            )
            .accessibilityHint(
                messageText.isEmpty
                ? L10n.string(
                    "content.accessibility.send_hint_empty",
                    comment: "Hint prompting the user to enter a message"
                )
                : L10n.string(
                    "content.accessibility.send_hint_ready",
                    comment: "Hint prompting the user to send the message"
                )
            )
            }
            .padding(.vertical, 8)
            .background(backgroundColor.opacity(0.95))
        }
        .onAppear {
            // Delay keyboard focus to avoid iOS constraint warnings
            DispatchQueue.main.asyncAfter(deadline: .now() + TransportConfig.uiReadReceiptRetryShortSeconds) {
                isTextFieldFocused = true
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        viewModel.sendMessage(messageText)
        messageText = ""
    }
    
    // MARK: - Sidebar View
    
    private var sidebarView: some View {
        HStack(spacing: 0) {
            // Grey vertical bar for visual continuity
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
            
            VStack(alignment: .leading, spacing: 0) {
                // Header - match main toolbar height
                HStack {
        Text("content.header.people")
                        .font(.bitchatSystem(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor)
                    Spacer()
                    // Show QR in mesh on all platforms
                    if case .mesh = locationManager.selectedChannel {
                        Button(action: { showVerifySheet = true }) {
                            Image(systemName: "qrcode")
                                .font(.bitchatSystem(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help(
                            L10n.string(
                                "content.help.verification",
                                comment: "Help text for verification button"
                            )
                        )
                    }
                }
                .frame(height: headerHeight) // Match header height
                .padding(.horizontal, 12)
                .background(backgroundColor.opacity(0.95))
                
                Divider()
            
            // Rooms and People list
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // People section
                    VStack(alignment: .leading, spacing: 4) {
                if case .location = locationManager.selectedChannel {
                    GeohashPeopleList(viewModel: viewModel,
                                      textColor: textColor,
                                      secondaryTextColor: secondaryTextColor,
                                      onTapPerson: {
                                          withAnimation(.easeInOut(duration: 0.2)) {
                                              showSidebar = false
                                              sidebarDragOffset = 0
                                          }
                                      })
                } else {
                    MeshPeerList(viewModel: viewModel,
                                 textColor: textColor,
                                 secondaryTextColor: secondaryTextColor,
                                 onTapPeer: { peerID in
                                     viewModel.startPrivateChat(with: peerID)
                                     withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                                         showSidebar = false
                                         sidebarDragOffset = 0
                                     }
                                 },
                                 onToggleFavorite: { peerID in
                                     viewModel.toggleFavorite(peerID: peerID)
                                 },
                                 onShowFingerprint: { peerID in
                                     viewModel.showFingerprint(for: peerID)
                                 })
                }
                    }
                }
                .id(viewModel.allPeers.map { "\($0.id)-\($0.isConnected)" }.joined())
            }
            
            Spacer()
        }
        .background(backgroundColor)
        }
    }
    
    // MARK: - View Components
    
    private var mainChatView: some View {
        VStack(spacing: 0) {
            mainHeaderView
            Divider()
            messagesView(privatePeer: nil, isAtBottom: $isAtBottomPublic)
            Divider()
            inputView
        }
        .background(backgroundColor)
        .foregroundColor(textColor)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.width.isNaN ? 0 : value.translation.width
                    if !showSidebar && translation < 0 {
                        sidebarDragOffset = max(translation, -300)
                    } else if showSidebar && translation > 0 {
                        sidebarDragOffset = min(-300 + translation, 0)
                    }
                }
                .onEnded { value in
                    let translation = value.translation.width.isNaN ? 0 : value.translation.width
                    let velocity = value.velocity.width.isNaN ? 0 : value.velocity.width
                    withAnimation(.easeOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                        if !showSidebar {
                            if translation < -100 || (translation < -50 && velocity < -500) {
                                showSidebar = true
                                sidebarDragOffset = 0
                            } else {
                                sidebarDragOffset = 0
                            }
                        } else {
                            if translation > 100 || (translation > 50 && velocity > 500) {
                                showSidebar = false
                                sidebarDragOffset = 0
                            } else {
                                sidebarDragOffset = 0
                            }
                        }
                    }
                }
        )
    }
    
    private var privateChatView: some View {
        HStack(spacing: 0) {
            // Vertical separator bar
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
            
            VStack(spacing: 0) {
                privateHeaderView
                Divider()
                messagesView(privatePeer: viewModel.selectedPrivateChatPeer, isAtBottom: $isAtBottomPrivate)
                Divider()
                inputView
            }
            .background(backgroundColor)
            .foregroundColor(textColor)
        }
    }

    // Split a name into base and a '#abcd' suffix if present
    private func splitNameSuffix(_ name: String) -> (base: String, suffix: String) {
        guard name.count >= 5 else { return (name, "") }
        let suffix = String(name.suffix(5))
        if suffix.first == "#", suffix.dropFirst().allSatisfy({ c in
            ("0"..."9").contains(String(c)) || ("a"..."f").contains(String(c)) || ("A"..."F").contains(String(c))
        }) {
            let base = String(name.dropLast(5))
            return (base, suffix)
        }
        return (name, "")
    }
    
    // Compute channel-aware people count and color for toolbar (cross-platform)
    private func channelPeopleCountAndColor() -> (Int, Color) {
        switch locationManager.selectedChannel {
        case .location:
            let n = viewModel.geohashPeople.count
            let standardGreen = (colorScheme == .dark) ? Color.green : Color(red: 0, green: 0.5, blue: 0)
            return (n, n > 0 ? standardGreen : Color.secondary)
        case .mesh:
            let counts = viewModel.allPeers.reduce(into: (others: 0, mesh: 0)) { counts, peer in
                guard peer.id != viewModel.meshService.myPeerID else { return }
                if peer.isConnected { counts.mesh += 1; counts.others += 1 }
                else if peer.isReachable { counts.others += 1 }
            }
            let meshBlue = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
            let color: Color = counts.mesh > 0 ? meshBlue : Color.secondary
            return (counts.others, color)
        }
    }

    
    private var mainHeaderView: some View {
        HStack(spacing: 0) {
            Text("bitchat/")
                .font(.bitchatSystem(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
                .onTapGesture(count: 3) {
                    // PANIC: Triple-tap to clear all data
                    viewModel.panicClearAllData()
                }
                .onTapGesture(count: 1) {
                    // Single tap for app info
                    showAppInfo = true
                }
            
            HStack(spacing: 0) {
                Text("@")
                    .font(.bitchatSystem(size: 14, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                
                TextField("content.input.nickname_placeholder", text: $viewModel.nickname)
                    .textFieldStyle(.plain)
                    .font(.bitchatSystem(size: 14, design: .monospaced))
                    .frame(maxWidth: 80)
                    .foregroundColor(textColor)
                    .focused($isNicknameFieldFocused)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: isNicknameFieldFocused) { isFocused in
                        if !isFocused {
                            // Only validate when losing focus
                            viewModel.validateAndSaveNickname()
                        }
                    }
                    .onSubmit {
                        viewModel.validateAndSaveNickname()
                    }
            }
            
            Spacer()
            
            // Channel badge + dynamic spacing + people counter
            // Precompute header count and color outside the ViewBuilder expressions
            let cc = channelPeopleCountAndColor()
            let headerCountColor: Color = cc.1
            let headerOtherPeersCount: Int = {
                if case .location = locationManager.selectedChannel {
                    return viewModel.visibleGeohashPeople().count
                }
                return cc.0
            }()

            HStack(spacing: 10) {
                // Unread icon immediately to the left of the channel badge (independent from channel button)
                
                // Unread indicator (now shown on iOS and macOS)
                if viewModel.hasAnyUnreadMessages {
                    Button(action: { viewModel.openMostRelevantPrivateChat() }) {
                        Image(systemName: "envelope.fill")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(Color.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        L10n.string(
                            "content.accessibility.open_unread_private_chat",
                            comment: "Accessibility label for the unread private chat button"
                        )
                    )
                }
                // Notes icon (mesh only and when location is authorized), to the left of #mesh
                if case .mesh = locationManager.selectedChannel, locationManager.permissionState == .authorized {
                    Button(action: {
                        // Kick a one-shot refresh and show the sheet immediately.
                        LocationChannelManager.shared.enableLocationChannels()
                        LocationChannelManager.shared.refreshChannels()
                        // If we already have a block geohash, pass it; otherwise wait in the sheet.
                        notesGeohash = LocationChannelManager.shared.availableChannels.first(where: { $0.level == .building })?.geohash
                        showLocationNotes = true
                    }) {
                        HStack(alignment: .center, spacing: 4) {
                            let currentCount = (notesCounter.count ?? 0)
                            let hasNotes = (!notesCounter.initialLoadComplete ? max(currentCount, sheetNotesCount) : currentCount) > 0
                            Image(systemName: "long.text.page.and.pencil")
                                .font(.bitchatSystem(size: 12))
                                .foregroundColor(hasNotes ? textColor : Color.gray)
                                .padding(.top, 1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        L10n.string(
                            "content.accessibility.location_notes",
                            comment: "Accessibility label for location notes button"
                        )
                    )
                }

                // Bookmark toggle (geochats): to the left of #geohash
                if case .location(let ch) = locationManager.selectedChannel {
                    Button(action: { GeohashBookmarksStore.shared.toggle(ch.geohash) }) {
                        Image(systemName: GeohashBookmarksStore.shared.isBookmarked(ch.geohash) ? "bookmark.fill" : "bookmark")
                            .font(.bitchatSystem(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        L10n.string(
                            "content.accessibility.toggle_bookmark",
                            comment: "Accessibility label for toggling a geohash bookmark",
                            ch.geohash
                        )
                    )
                }

                // Location channels button '#'
                Button(action: { showLocationChannelsSheet = true }) {
                    let badgeText: String = {
                        switch locationManager.selectedChannel {
                        case .mesh: return "#mesh"
                        case .location(let ch): return "#\(ch.geohash)"
                        }
                    }()
                    let badgeColor: Color = {
                        switch locationManager.selectedChannel {
                        case .mesh:
                            return Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
                        case .location:
                            return (colorScheme == .dark) ? Color.green : Color(red: 0, green: 0.5, blue: 0)
                        }
                    }()
                    Text(badgeText)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(badgeColor)
                        .lineLimit(headerLineLimit)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                        .accessibilityLabel(
                            L10n.string(
                                "content.accessibility.location_channels",
                                comment: "Accessibility label for the location channels button"
                            )
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.trailing, 2)

                HStack(spacing: 4) {
                    // People icon with count
                    Image(systemName: "person.2.fill")
                        .font(.system(size: headerPeerIconSize, weight: .regular))
                        .accessibilityLabel(
                            L10n.string(
                                "content.accessibility.people_count",
                                comment: "Accessibility label announcing number of people in header",
                                headerOtherPeersCount
                            )
                        )
                    Text("\(headerOtherPeersCount)")
                        .font(.system(size: headerPeerCountFontSize, weight: .regular, design: .monospaced))
                        .accessibilityHidden(true)
                }
                .foregroundColor(headerCountColor)
                .padding(.leading, 2)
                .lineLimit(headerLineLimit)
                .fixedSize(horizontal: true, vertical: false)

                // QR moved to the PEOPLE header in the sidebar when on mesh channel
            }
            .layoutPriority(3)
            .onTapGesture {
                withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                    showSidebar.toggle()
                    sidebarDragOffset = 0
                }
            }
            .sheet(isPresented: $showVerifySheet) {
                VerificationSheetView(isPresented: $showVerifySheet)
                    .environmentObject(viewModel)
            }
        }
        .frame(height: headerHeight)
        .padding(.horizontal, 12)
        .sheet(isPresented: $showLocationChannelsSheet) {
            LocationChannelsSheet(isPresented: $showLocationChannelsSheet)
                .onAppear { viewModel.isLocationChannelsSheetPresented = true }
                .onDisappear { viewModel.isLocationChannelsSheetPresented = false }
        }
        .sheet(isPresented: $showLocationNotes) {
            Group {
                if let gh = notesGeohash ?? LocationChannelManager.shared.availableChannels.first(where: { $0.level == .building })?.geohash {
                    LocationNotesView(geohash: gh, onNotesCountChanged: { cnt in sheetNotesCount = cnt })
                        .environmentObject(viewModel)
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Text("content.notes.title")
                                .font(.bitchatSystem(size: 16, weight: .bold, design: .monospaced))
                            Spacer()
                            Button(action: { showLocationNotes = false }) {
                                Image(systemName: "xmark")
                                    .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(textColor)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.string(
                                "common.close",
                                comment: "Accessibility label for close buttons"
                            ))
                        }
                        .frame(height: headerHeight)
                        .padding(.horizontal, 12)
                        .background(backgroundColor.opacity(0.95))
                        Text("content.notes.location_unavailable")
                            .font(.bitchatSystem(size: 14, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        Button("content.location.enable") {
                            LocationChannelManager.shared.enableLocationChannels()
                            LocationChannelManager.shared.refreshChannels()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    // per-sheet global onChange added below
                }
            }
            .onAppear {
                // Ensure we are authorized and start live location updates (distance-filtered)
                LocationChannelManager.shared.enableLocationChannels()
                LocationChannelManager.shared.beginLiveRefresh()
            }
            .onDisappear {
                LocationChannelManager.shared.endLiveRefresh()
            }
            .onChange(of: locationManager.availableChannels) { channels in
                if let current = channels.first(where: { $0.level == .building })?.geohash,
                    notesGeohash != current {
                    notesGeohash = current
                    #if os(iOS)
                    // Light taptic when geohash changes while the sheet is open
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    #endif
                }
            }
        }
        .onAppear {
            updateNotesCounterSubscription()
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .onChange(of: locationManager.selectedChannel) { _ in
            updateNotesCounterSubscription()
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .onChange(of: locationManager.availableChannels) { _ in updateNotesCounterSubscription() }
        .onChange(of: locationManager.permissionState) { _ in
            updateNotesCounterSubscription()
            if case .mesh = locationManager.selectedChannel,
               locationManager.permissionState == .authorized,
               LocationChannelManager.shared.availableChannels.isEmpty {
                LocationChannelManager.shared.refreshChannels()
            }
        }
        .alert("content.alert.screenshot.title", isPresented: $viewModel.showScreenshotPrivacyWarning) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("content.alert.screenshot.message")
        }
        .background(backgroundColor.opacity(0.95))
    }
    
    private var privateHeaderView: some View {
        Group {
            if let privatePeerID = viewModel.selectedPrivateChatPeer {
                privateHeaderContent(for: privatePeerID)
            }
        }
    }
    
    @ViewBuilder
    private func privateHeaderContent(for privatePeerID: String) -> some View {
        // Prefer short (mesh) ID whenever available for encryption/session status; keep stable key for display resolution only.
        let headerPeerID: String = {
            if privatePeerID.count == 64 {
                // Map stable Noise key to short ID if we know it (even if not directly connected)
                if let short = viewModel.getShortIDForNoiseKey(privatePeerID) { return short }
            }
            return privatePeerID
        }()
        
        // Resolve peer object for header context (may be offline favorite)
        let peer = viewModel.getPeer(byID: headerPeerID)
        let privatePeerNick: String = {
            if privatePeerID.hasPrefix("nostr_") {
                // Build geohash DM header: "#<ghash>/@name#abcd"
                if case .location(let ch) = locationManager.selectedChannel {
                    let disp = viewModel.geohashDisplayName(for: privatePeerID)
                    return "#\(ch.geohash)/@\(disp)"
                }
            }
            // Try mesh/unified peer display
            if let name = peer?.displayName { return name }
            // Try direct mesh nickname (connected-only)
            if let name = viewModel.meshService.peerNickname(peerID: headerPeerID) { return name }
            // Try favorite nickname by stable Noise key
            if let fav = FavoritesPersistenceService.shared.getFavoriteStatus(for: Data(hexString: headerPeerID) ?? Data()),
               !fav.peerNickname.isEmpty { return fav.peerNickname }
            // Fallback: resolve from persisted social identity via fingerprint mapping
            if headerPeerID.count == 16 {
                let candidates = viewModel.identityManager.getCryptoIdentitiesByPeerIDPrefix(headerPeerID)
                if let id = candidates.first,
                   let social = viewModel.identityManager.getSocialIdentity(for: id.fingerprint) {
                    if let pet = social.localPetname, !pet.isEmpty { return pet }
                    if !social.claimedNickname.isEmpty { return social.claimedNickname }
                }
            } else if headerPeerID.count == 64, let keyData = Data(hexString: headerPeerID) {
                let fp = keyData.sha256Fingerprint()
                if let social = viewModel.identityManager.getSocialIdentity(for: fp) {
                    if let pet = social.localPetname, !pet.isEmpty { return pet }
                    if !social.claimedNickname.isEmpty { return social.claimedNickname }
                }
            }
            return L10n.string(
                "common.unknown",
                comment: "Fallback label for unknown peer"
            )
        }()
        let isNostrAvailable: Bool = {
            guard let connectionState = peer?.connectionState else { 
                // Check if we can reach this peer via Nostr even if not in allPeers
                if let noiseKey = Data(hexString: headerPeerID),
                   let favoriteStatus = FavoritesPersistenceService.shared.getFavoriteStatus(for: noiseKey),
                   favoriteStatus.isMutual {
                    return true
                }
                return false 
            }
            switch connectionState {
            case .nostrAvailable:
                return true
            default:
                return false
            }
        }()
        
        ZStack {
                    // Center content - always perfectly centered
                    Button(action: {
                        viewModel.showFingerprint(for: headerPeerID)
                    }) {
                        HStack(spacing: 6) {
                            // Show transport icon based on connection state (like peer list)
                            if let connectionState = peer?.connectionState {
                                switch connectionState {
                                case .bluetoothConnected:
                                    // Radio icon for mesh connection
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.bitchatSystem(size: 14))
                                        .foregroundColor(textColor)
                                        .accessibilityLabel(
                                            L10n.string(
                                                "content.accessibility.connected_mesh",
                                                comment: "Accessibility label for mesh-connected peer indicator"
                                            )
                                        )
                                case .meshReachable:
                                    // point.3 filled icon for reachable via mesh (not directly connected)
                                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                        .font(.bitchatSystem(size: 14))
                                        .foregroundColor(textColor)
                                        .accessibilityLabel(
                                            L10n.string(
                                                "content.accessibility.reachable_mesh",
                                                comment: "Accessibility label for mesh-reachable peer indicator"
                                            )
                                        )
                                case .nostrAvailable:
                                    // Purple globe for Nostr
                                    Image(systemName: "globe")
                                        .font(.bitchatSystem(size: 14))
                                        .foregroundColor(.purple)
                                        .accessibilityLabel(
                                            L10n.string(
                                                "content.accessibility.available_nostr",
                                                comment: "Accessibility label for Nostr-available peer indicator"
                                            )
                                        )
                                case .offline:
                                    // Should not happen for PM header, but handle gracefully
                                    EmptyView()
                                }
                            } else if viewModel.meshService.isPeerReachable(headerPeerID) {
                                // Fallback: reachable via mesh but not in current peer list
                                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                    .font(.bitchatSystem(size: 14))
                                    .foregroundColor(textColor)
                                    .accessibilityLabel(
                                        L10n.string(
                                            "content.accessibility.reachable_mesh",
                                            comment: "Accessibility label for mesh-reachable peer indicator"
                                        )
                                    )
                            } else if isNostrAvailable {
                                // Fallback to Nostr if peer not in list but is mutual favorite
                                Image(systemName: "globe")
                                    .font(.bitchatSystem(size: 14))
                                    .foregroundColor(.purple)
                                    .accessibilityLabel(
                                        L10n.string(
                                            "content.accessibility.available_nostr",
                                            comment: "Accessibility label for Nostr-available peer indicator"
                                        )
                                    )
                            } else if viewModel.meshService.isPeerConnected(headerPeerID) || viewModel.connectedPeers.contains(headerPeerID) {
                                // Fallback: if peer lookup is missing but mesh reports connected, show radio
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.bitchatSystem(size: 14))
                                    .foregroundColor(textColor)
                                    .accessibilityLabel(
                                        L10n.string(
                                            "content.accessibility.connected_mesh",
                                            comment: "Accessibility label for mesh-connected peer indicator"
                                        )
                                    )
                            }
                            
                            Text("\(privatePeerNick)")
                                .font(.bitchatSystem(size: 16, weight: .medium, design: .monospaced))
                                .foregroundColor(textColor)                            // Dynamic encryption status icon (hide for geohash DMs)
                            if !privatePeerID.hasPrefix("nostr_") {
                                // Use short peer ID if available for encryption status (sessions keyed by short ID)
                                let statusPeerID: String = {
                                    if privatePeerID.count == 64, let short = viewModel.getShortIDForNoiseKey(privatePeerID) {
                                        return short
                                    }
                                    return headerPeerID
                                }()
                                let encryptionStatus = viewModel.getEncryptionStatus(for: statusPeerID)
                                if let icon = encryptionStatus.icon {
                                    Image(systemName: icon)
                                        .font(.bitchatSystem(size: 14))
                                        .foregroundColor(encryptionStatus == .noiseVerified ? textColor : 
                                                       encryptionStatus == .noiseSecured ? textColor :
                                                       Color.red)
                                        .accessibilityLabel(
                                            L10n.string(
                                                "content.accessibility.encryption_status",
                                                comment: "Accessibility label announcing encryption status",
                                                encryptionStatus.accessibilityDescription
                                            )
                                        )
                                }
                            }
                        }
                        .accessibilityLabel(
                            L10n.string(
                                "content.accessibility.private_chat_header",
                                comment: "Accessibility label describing the private chat header",
                                privatePeerNick
                            )
                        )
                        .accessibilityHint(
                            L10n.string(
                                "content.accessibility.view_fingerprint_hint",
                                comment: "Accessibility hint for viewing encryption fingerprint"
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Left and right buttons positioned with HStack
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                                showPrivateChat = false
                                viewModel.endPrivateChat()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.bitchatSystem(size: 12))
                                .foregroundColor(textColor)
                                .frame(width: 44, height: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            L10n.string(
                                "content.accessibility.back_to_main_chat",
                                comment: "Accessibility label for returning to main chat"
                            )
                        )
                        
                        Spacer()
                        
                        // Favorite button (hidden for geohash DMs)
                        if !(privatePeerID.hasPrefix("nostr_")) {
                            Button(action: {
                                viewModel.toggleFavorite(peerID: headerPeerID)
                            }) {
                                Image(systemName: viewModel.isFavorite(peerID: headerPeerID) ? "star.fill" : "star")
                                    .font(.bitchatSystem(size: 16))
                                    .foregroundColor(viewModel.isFavorite(peerID: headerPeerID) ? Color.yellow : textColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                viewModel.isFavorite(peerID: privatePeerID)
                                ? L10n.string(
                                    "content.accessibility.remove_favorite",
                                    comment: "Accessibility label to remove a favorite"
                                )
                                : L10n.string(
                                    "content.accessibility.add_favorite",
                                    comment: "Accessibility label to add a favorite"
                                )
                            )
                            .accessibilityHint(
                                L10n.string(
                                    "content.accessibility.toggle_favorite_hint",
                                    comment: "Accessibility hint for toggling favorite status"
                                )
                            )
                        }
                    }
                }
                .frame(height: headerHeight)
                .padding(.horizontal, 12)
                .background(backgroundColor.opacity(0.95))
    }
    
}

// MARK: - Notes Counter Subscription Helper
extension ContentView {
    private func updateNotesCounterSubscription() {
        switch locationManager.selectedChannel {
        case .mesh:
            // Ensure we have a fresh one-shot location fix so building geohash is current
            if locationManager.permissionState == .authorized {
                LocationChannelManager.shared.refreshChannels()
            }
            if locationManager.permissionState == .authorized {
                if let building = LocationChannelManager.shared.availableChannels.first(where: { $0.level == .building })?.geohash {
                    LocationNotesCounter.shared.subscribe(geohash: building)
                } else {
                    // Keep existing subscription if we had one to avoid flicker
                    // Only cancel if we have no known geohash
                    if LocationNotesCounter.shared.geohash == nil {
                        LocationNotesCounter.shared.cancel()
                    }
                }
            } else {
                LocationNotesCounter.shared.cancel()
            }
        case .location:
            LocationNotesCounter.shared.cancel()
        }
    }
}

// MARK: - Helper Views

// Rounded payment chip button
private struct PaymentChipView: View {
    let emoji: String
    let label: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    private var fgColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    private var bgColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.18) : Color.gray.opacity(0.12)
    }
    private var border: Color { fgColor.opacity(0.25) }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(label)
                    .font(.bitchatSystem(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(border, lineWidth: 1)
            )
            .foregroundColor(fgColor)
        }
        .buttonStyle(.plain)
    }
}

//

// Delivery status indicator view
struct DeliveryStatusView: View {
    let status: DeliveryStatus
    let colorScheme: ColorScheme
    
    // MARK: - Computed Properties
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }

    private enum Strings {
        static func delivered(to nickname: String) -> String {
            L10n.string(
                "content.delivery.delivered_to",
                comment: "Tooltip for delivered private messages",
                nickname
            )
        }

        static func read(by nickname: String) -> String {
            L10n.string(
                "content.delivery.read_by",
                comment: "Tooltip for read private messages",
                nickname
            )
        }

        static func failed(_ reason: String) -> String {
            L10n.string(
                "content.delivery.failed",
                comment: "Tooltip for failed message delivery",
                reason
            )
        }

        static func deliveredToMembers(_ reached: Int, _ total: Int) -> String {
            L10n.string(
                "content.delivery.delivered_members",
                comment: "Tooltip for partially delivered messages",
                reached,
                total
            )
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        switch status {
        case .sending:
            Image(systemName: "circle")
                .font(.bitchatSystem(size: 10))
                .foregroundColor(secondaryTextColor.opacity(0.6))
            
        case .sent:
            Image(systemName: "checkmark")
                .font(.bitchatSystem(size: 10))
                .foregroundColor(secondaryTextColor.opacity(0.6))
            
        case .delivered(let nickname, _):
            HStack(spacing: -2) {
                Image(systemName: "checkmark")
                    .font(.bitchatSystem(size: 10))
                Image(systemName: "checkmark")
                    .font(.bitchatSystem(size: 10))
            }
            .foregroundColor(textColor.opacity(0.8))
            .help(Strings.delivered(to: nickname))
            
        case .read(let nickname, _):
            HStack(spacing: -2) {
                Image(systemName: "checkmark")
                    .font(.bitchatSystem(size: 10, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.bitchatSystem(size: 10, weight: .bold))
            }
            .foregroundColor(Color(red: 0.0, green: 0.478, blue: 1.0))  // Bright blue
            .help(Strings.read(by: nickname))
            
        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle")
                .font(.bitchatSystem(size: 10))
                .foregroundColor(Color.red.opacity(0.8))
                .help(Strings.failed(reason))
            
        case .partiallyDelivered(let reached, let total):
            HStack(spacing: 1) {
                Image(systemName: "checkmark")
                    .font(.bitchatSystem(size: 10))
                Text("\(reached)/\(total)")
                    .font(.bitchatSystem(size: 10, design: .monospaced))
            }
            .foregroundColor(secondaryTextColor.opacity(0.6))
            .help(Strings.deliveredToMembers(reached, total))
        }
    }
}

import SwiftUI
import Observation

/// The single @Observable app model. Owns all conversation/network state, the
/// active selection, and the composer/quick-switcher UI state. It consumes the
/// `IRCClient` event stream and turns user intents into client calls.
///
/// Swap the transport here — this is the "one-line change":
///
///     private let client: IRCClient = MockIRCService()
///     // → LiveIRCClient(networkID: "undernet", host: "irc.undernet.org", port: 6697, nick: "mcimpeanu")
///
@MainActor
@Observable
final class AppModel {

    // Multiplexing transport: in-memory mock for the demo networks, real live
    // sockets for any server whose config opts out of the mock.
    let hub = IRCHub()
    var client: IRCClient { hub }

    static let selfNickPlaceholder = NSUserName().isEmpty ? "relay" : NSUserName()

    // MARK: World state (built from serverConfigs in buildWorld)
    var networks: [Network] = []
    var conversations: [String: Conversation] = [:]
    var selectedID: String = ""

    // MARK: UI state
    var sidebarVisible = true
    var memberListVisible = true
    var quickSwitcherOpen = false
    var searchOpen = false
    var searchText = ""
    var connectingLog: [String] = []
    var channelModesOpen = false
    var xSettingsOpen = false
    var channelListOpen = false
    var channelList: [ChannelListItem] = []
    var commandPrompt: CommandPrompt?
    var joinFailure: JoinFailure?
    /// Set to a nick to highlight + scroll it in the member list (cleared there).
    var revealedMember: String?
    @ObservationIgnored private var whoisTargetConvID: String?

    // Composer input history (↑/↓ recall), auto-reconnect and private-session
    // bookkeeping, and the Notification Center bridge.
    @ObservationIgnored var inputHistory: [String] = []
    @ObservationIgnored private var reconnectAttempts: [String: Int] = [:]
    @ObservationIgnored private var reconnectTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var intentionalDisconnect: Set<String> = []
    @ObservationIgnored private var privateModeNetworks: Set<String> = []
    @ObservationIgnored private var pendingPrivateChannel: [String: String] = [:]
    @ObservationIgnored let notifier = NotificationManager()

    // Persisted server configurations — the durable records behind `networks`.
    var serverConfigs: [ServerConfig] = []
    private static let serversKey = "relay.serverConfigs.v3"

    // User-defined ASCII art (persisted), shown alongside the built-in catalog.
    var customArt: [ArtLine] = []
    private static let artKey = "relay.customArt.v1"

    // Extra words (besides your nick) that trigger the mention highlight/badge.
    var highlightKeywords: [String] = []
    private static let keywordsKey = "relay.highlightKeywords.v1"

    // Client-side ignore list — messages from these nicks are dropped.
    var ignoredNicks: [String] = []
    private static let ignoredKey = "relay.ignoredNicks.v1"

    init() {
        loadServers()
        buildWorld()
        loadCustomArt()
        if let data = UserDefaults.standard.data(forKey: AppModel.keywordsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            highlightKeywords = decoded
        }
        if let data = UserDefaults.standard.data(forKey: AppModel.ignoredKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ignoredNicks = decoded
        }
        notifier.onSelect = { [weak self] convID in self?.select(convID) }
        notifier.start()
        Task { await consumeEvents() }
        startAutoConnect()
    }

    func saveKeywords() {
        if let data = try? JSONEncoder().encode(highlightKeywords) {
            UserDefaults.standard.set(data, forKey: AppModel.keywordsKey)
        }
    }

    // Compiled once and reused until nick/keywords change — this runs for
    // every incoming message network-wide, and per-call regex compilation was
    // a measurable, growing main-thread cost.
    @ObservationIgnored private var highlightRegexKey = ""
    @ObservationIgnored private var highlightRegexCached: NSRegularExpression?

    /// Does this text mention you (your nick) or any highlight keyword?
    func isHighlight(_ text: String) -> Bool {
        let words = ([selfNick] + highlightKeywords).filter { !$0.isEmpty }
        let key = words.joined(separator: "\u{1}").lowercased()
        if key != highlightRegexKey {
            highlightRegexKey = key
            highlightRegexCached = words.isEmpty ? nil :
                try? NSRegularExpression(
                    pattern: "\\b(?:" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b",
                    options: [.caseInsensitive])
        }
        guard let regex = highlightRegexCached else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Build the runtime networks/conversations from `serverConfigs`. Every
    /// network starts disconnected with just its server console — real content
    /// arrives once you connect.
    private func buildWorld() {
        networks = []
        conversations = [:]
        for cfg in serverConfigs { ensureNetwork(for: cfg) }
        selectedID = networks.first?.serverConsoleID ?? ""
    }

    // MARK: Derived

    var selectedConversation: Conversation? { conversations[selectedID] }

    func network(for convID: String) -> Network? {
        let netID = String(convID.split(separator: "/").first ?? "")
        return networks.first { $0.id == netID }
    }
    var selectedNetwork: Network? { network(for: selectedID) }
    var selfNick: String { selectedNetwork?.nick ?? AppModel.selfNickPlaceholder }

    /// Flat, ordered list of selectable conversations (skips server consoles) —
    /// used by ⌘1–9 and the quick switcher.
    var flatConversations: [(conv: Conversation, network: Network)] {
        var out: [(Conversation, Network)] = []
        for net in networks {
            for id in net.conversationIDs {
                if let c = conversations[id], c.kind != .server { out.append((c, net)) }
            }
        }
        return out
    }

    // MARK: Event consumption

    private func consumeEvents() async {
        for await event in client.events {
            apply(event)
        }
    }

    private func apply(_ event: IRCEvent) {
        switch event {
        case let .stateChanged(networkID, state):
            let was = self.state(of: networkID)
            mutateNetwork(networkID) { $0.state = state }
            if state == .connected {
                connectingLog = []
                reconnectAttempts[networkID] = 0
                if was != .connected { performOnConnect(networkID) }
            } else if state == .disconnected, was != nil, was != .disconnected {
                scheduleReconnectIfNeeded(networkID)
            }

        case let .serverLine(networkID, text):
            if state(of: networkID)?.isBusy == true {
                connectingLog.append(text)
            }
            appendMessage(to: "\(networkID)/$server", Message(id: UUID().uuidString, kind: .server, text: text))

        case let .message(convID, message):
            guard message.nick.isEmpty || !isIgnored(message.nick) else { return }
            ensureConversation(convID)
            // DMs display the peer's actual nick casing (x → X as they use it).
            mutateConversation(convID) {
                if $0.kind == .directMessage, !message.nick.isEmpty,
                   $0.name.caseInsensitiveCompare(message.nick) == .orderedSame,
                   $0.name != message.nick {
                    $0.name = message.nick
                }
            }
            appendMessage(to: convID, message, incoming: message.nick != selfNick)

        case let .topic(convID, topic):
            mutateConversation(convID) { $0.topic = topic }

        case let .members(convID, members):
            mutateConversation(convID) { $0.members = members }

        case let .memberJoined(convID, member):
            ensureConversation(convID)
            // JOIN carries the server's canonical channel casing — adopt it
            // for display (the conversation ID stays stable).
            let serverName = String(convID.dropFirst(networkID(of: convID).count + 1))
            mutateConversation(convID) {
                if !$0.members.contains(where: { $0.nick == member.nick }) { $0.members.append(member) }
                if $0.kind == .channel, $0.name != serverName { $0.name = serverName }
            }
            appendMessage(to: convID, Message(id: UUID().uuidString, kind: .join, nick: member.nick, text: "joined"),
                          incoming: member.nick != selfNick)

        case let .memberLeft(convID, nick, reason, kind):
            mutateConversation(convID) { $0.members.removeAll { $0.nick == nick } }
            appendMessage(to: convID, Message(id: UUID().uuidString, kind: kind, nick: nick, text: reason),
                          incoming: nick != selfNick)

        case let .userQuit(networkID, nick, reason):
            for (cid, conv) in conversations
            where self.networkID(of: cid) == networkID && conv.kind == .channel
                  && conv.members.contains(where: { $0.nick == nick }) {
                mutateConversation(cid) { $0.members.removeAll { $0.nick == nick } }
                appendMessage(to: cid, Message(id: UUID().uuidString, kind: .quit, nick: nick, text: reason),
                              incoming: true)
            }

        case let .modeChanged(convID, nick, mode):
            mutateConversation(convID) {
                if let i = $0.members.firstIndex(where: { $0.nick == nick }) { $0.members[i].mode = mode }
            }

        case let .channelModeChanged(convID, letter, enabled, arg):
            mutateConversation(convID) {
                if enabled {
                    $0.activeModes.insert(letter)
                    if letter == "l" { $0.modeLimit = Int(arg ?? "") }
                    if letter == "k" { $0.modeKey = arg }
                } else {
                    $0.activeModes.remove(letter)
                    if letter == "l" { $0.modeLimit = nil }
                    if letter == "k" { $0.modeKey = nil }
                }
            }

        case let .channelList(_, items):
            channelList = items
            channelListOpen = true

        case let .whois(networkID, text):
            let cid = whoisTargetConvID ?? "\(networkID)/$server"
            appendMessage(to: cid, Message(id: UUID().uuidString, kind: .whois, text: text))

        case let .banList(convID, masks):
            mutateConversation(convID) { $0.bans = masks }

        case let .ban(convID, mask, added):
            mutateConversation(convID) {
                if added { if !$0.bans.contains(mask) { $0.bans.append(mask) } }
                else { $0.bans.removeAll { $0 == mask } }
            }
            appendMessage(to: convID, Message(id: UUID().uuidString, kind: .server,
                                              text: "*** \(mask) was \(added ? "banned" : "unbanned")"),
                          incoming: true)

        case let .nickChanged(networkID, from, to):
            // Update our own nick only if it was ours.
            if networks.first(where: { $0.id == networkID })?.nick == from {
                mutateNetwork(networkID) { $0.nick = to }
            }
            // Rename the member in every channel they're in, and log it.
            for (cid, conv) in conversations
            where self.networkID(of: cid) == networkID && conv.kind == .channel
                  && conv.members.contains(where: { $0.nick == from }) {
                mutateConversation(cid) {
                    if let i = $0.members.firstIndex(where: { $0.nick == from }) { $0.members[i].nick = to }
                }
                appendMessage(to: cid, Message(id: UUID().uuidString, kind: .server, text: "\(from) is now known as \(to)"))
            }

        case let .joinFailed(networkID, channel, code, reason):
            let cid = "\(networkID)/\(channel)"
            ensureConversation(cid)
            appendMessage(to: cid, Message(id: UUID().uuidString, kind: .server,
                                           text: "*** Cannot join \(channel): \(reason)"))
            joinFailure = JoinFailure(networkID: networkID, channel: channel, code: code, reason: reason)
        }
    }

    /// IRC channel names are case-insensitive, but the server echoes its own
    /// canonical casing (JOIN #romania → :you JOIN #Romania). Map any casing
    /// onto the conversation that already exists so we never split one channel
    /// into two.
    private func canonicalConvID(_ id: String) -> String {
        if conversations[id] != nil { return id }
        let lower = id.lowercased()
        return conversations.keys.first { $0.lowercased() == lower } ?? id
    }

    /// Create a conversation (and surface it in the sidebar) if it doesn't exist
    /// yet — e.g. an incoming DM from someone new, or a service NOTICE.
    private func ensureConversation(_ convID: String) {
        let convID = canonicalConvID(convID)
        guard conversations[convID] == nil else { return }
        let netID = networkID(of: convID)
        guard networks.contains(where: { $0.id == netID }) else { return }
        let name = String(convID.dropFirst(netID.count + 1))
        let kind: ConversationKind = (name.hasPrefix("#") || name.hasPrefix("&")) ? .channel : .directMessage
        conversations[convID] = Conversation(id: convID, kind: kind, name: name)
        mutateNetwork(netID) { if !$0.conversationIDs.contains(convID) { $0.conversationIDs.append(convID) } }
    }

    private func state(of networkID: String) -> ConnectionState? {
        networks.first { $0.id == networkID }?.state
    }

    // MARK: Mutation helpers

    private func mutateNetwork(_ id: String, _ body: (inout Network) -> Void) {
        guard let i = networks.firstIndex(where: { $0.id == id }) else { return }
        body(&networks[i])
    }
    private func mutateConversation(_ id: String, _ body: (inout Conversation) -> Void) {
        let id = canonicalConvID(id)
        guard var c = conversations[id] else { return }
        body(&c)
        conversations[id] = c
    }

    private func appendMessage(to convID: String, _ message: Message, incoming: Bool = false) {
        let convID = canonicalConvID(convID)
        guard var c = conversations[convID] else { return }
        c.messages.append(message)
        // Cap scrollback so a flooded channel can't grow unboundedly laggy.
        if c.messages.count > 2000 { c.messages.removeFirst(c.messages.count - 1500) }
        let isChat = message.kind == .message || message.kind == .action
        // Red badge (mentions) only for nick/keyword hits in a channel.
        // DMs never set mentions → they show only the blue (general) badge.
        let mention = isChat && isHighlight(message.text)
        // Quiet conversations accrue no counters and post no notifications.
        if incoming && convID != selectedID && !c.isMuted && countsAsActivity(message, in: c) {
            c.unread += 1
            if c.firstUnreadID == nil { c.firstUnreadID = message.id }
            if mention && c.kind == .channel { c.mentions += 1 }
        }
        conversations[convID] = c
        // Notification Center: mentions + DMs (honoring the Settings toggles).
        // The delegate suppresses the banner while the app is frontmost, so
        // these only surface when the app is in the background.
        let wantMentions = UserDefaults.standard.object(forKey: "notifyMentions") as? Bool ?? true
        let wantDMs = UserDefaults.standard.object(forKey: "notifyDMs") as? Bool ?? true
        if incoming, isChat, !c.isMuted,
           (c.kind == .directMessage && wantDMs) || (c.kind == .channel && mention && wantMentions) {
            notifier.post(convID: convID,
                          title: c.kind == .channel ? "\(c.name) — \(message.nick)" : message.nick,
                          body: RichText.plain(message.text))
        }
        updateDockBadge()
    }

    /// Total unread across all conversations on the Dock icon (Settings toggle).
    private func updateDockBadge() {
        guard UserDefaults.standard.object(forKey: "dockBadge") as? Bool ?? true else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let total = conversations.values.reduce(0) { $0 + $1.unread }
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }

    /// In a channel, all activity (chat, joins/parts/quits/kicks, ban/mode
    /// lines) bumps the badge. In a DM, only real chat does — service notices
    /// shouldn't keep it "unread".
    private func countsAsActivity(_ m: Message, in conv: Conversation) -> Bool {
        switch m.kind {
        case .message, .action:       return true
        case .join, .part, .quit, .server: return conv.kind == .channel
        case .notice, .whois:         return false
        }
    }

    // MARK: Selection

    func select(_ id: String) {
        selectedID = id
        searchOpen = false; searchText = ""
        mutateConversation(id) { $0.unread = 0; $0.mentions = 0; $0.firstUnreadID = nil }
        updateDockBadge()
    }

    func selectIndex(_ oneBased: Int) {
        let list = flatConversations
        guard oneBased >= 1, oneBased <= list.count else { return }
        select(list[oneBased - 1].conv.id)
    }

    func toggleNetwork(_ id: String) { mutateNetwork(id) { $0.isExpanded.toggle() } }

    // MARK: Connection

    func connect(_ networkID: String) {
        intentionalDisconnect.remove(networkID)
        privateModeNetworks.remove(networkID)   // a manual Connect is a normal session
        cancelReconnect(networkID)
        Task { await hub.updateConfigs(serverConfigs); await hub.connect(networkID: networkID) }
    }
    func disconnect(_ networkID: String) {
        intentionalDisconnect.insert(networkID)
        privateModeNetworks.remove(networkID)
        cancelReconnect(networkID)
        reconnectAttempts[networkID] = 0
        Task { await hub.disconnect(networkID: networkID) }
    }

    // MARK: - Auto-reconnect (exponential backoff)

    private func cancelReconnect(_ networkID: String) {
        reconnectTasks[networkID]?.cancel()
        reconnectTasks[networkID] = nil
    }

    /// A socket dropped without the user asking: reconnect with exponential
    /// backoff (2s → 5min). On success the normal performOnConnect path runs —
    /// user modes and perform commands first (with their delays), THEN channel
    /// rejoin — identical to a manual connect.
    private func scheduleReconnectIfNeeded(_ networkID: String) {
        guard !intentionalDisconnect.contains(networkID) else { return }
        guard config(for: networkID)?.autoReconnect != false else { return }   // honor the per-server toggle
        let attempt = reconnectAttempts[networkID, default: 0] + 1
        reconnectAttempts[networkID] = attempt
        let delay = min(300.0, pow(2.0, Double(attempt)))
        appendMessage(to: "\(networkID)/$server",
                      Message(id: UUID().uuidString, kind: .server,
                              text: "*** Connection lost — reconnecting in \(Int(delay))s (attempt \(attempt))"))
        cancelReconnect(networkID)
        reconnectTasks[networkID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.state(of: networkID) == .disconnected else { return }
            self.appendMessage(to: "\(networkID)/$server",
                               Message(id: UUID().uuidString, kind: .server, text: "*** Reconnecting…"))
            await self.hub.updateConfigs(self.serverConfigs)
            await self.hub.connect(networkID: networkID)
        }
    }

    // MARK: Composer entry point — parse slash commands, else send

    func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if inputHistory.last != text {
            inputHistory.append(text)
            if inputHistory.count > 100 { inputHistory.removeFirst() }
        }
        if text.hasPrefix("/") { runCommand(text) }
        else {
            Task { await client.send(text: text, to: selectedID) }
            echoOwn(text, kind: .message, to: selectedID)
        }
    }

    /// IRC does not echo your own PRIVMSG/NOTICE back, so render it locally.
    private func echoOwn(_ text: String, kind: MessageKind, to convID: String) {
        appendMessage(to: convID, Message(id: UUID().uuidString, kind: kind, nick: selfNick, text: text))
    }

    private func runCommand(_ text: String) {
        let parts = text.dropFirst().split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let cmd = parts.first?.lowercased() ?? ""
        let rest = Array(parts.dropFirst())
        let arg = rest.joined(separator: " ")
        let netID = selectedNetwork?.id ?? ""

        switch cmd {
        case "me":    if !arg.isEmpty {
            Task { await client.sendAction(arg, to: selectedID) }
            echoOwn(arg, kind: .action, to: selectedID)
        }
        case "join":  if !arg.isEmpty { joinChannel(arg) }
        case "part":  partCurrent()
        case "nick":  if let n = rest.first { Task { await client.changeNick(n, networkID: netID) } }
        case "topic": Task { await client.setTopic(arg, conversationID: selectedID) }
        case "whois":
            whoisTargetConvID = selectedID
            Task { await client.whois(nick: rest.first ?? selfNick, conversationID: selectedID) }
        case "list":
            Task { await client.sendRaw(arg.isEmpty ? "LIST" : "LIST \(arg)", networkID: netID) }
        case "ban":   if let n = rest.first { banNick(n) }
        case "unban": if let n = rest.first { unbanNick(n) }
        case "invite":
            // /invite <nick> [#channel]  (defaults to the current channel)
            if let nick = rest.first {
                let chan = rest.count > 1 ? rest[1] : (selectedConversation?.kind == .channel ? selectedConversation!.name : "")
                guard !chan.isEmpty else { break }
                Task { await client.sendRaw("INVITE \(nick) \(chan)", networkID: netID) }
                appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** Invited \(nick) to \(chan)"))
            }
        case "ctcp":
            // /ctcp <target> <COMMAND> [args]
            if rest.count >= 2 {
                let target = rest[0]
                let payload = rest.dropFirst().joined(separator: " ")
                Task { await client.sendRaw("PRIVMSG \(target) :\u{01}\(payload)\u{01}", networkID: netID) }
                appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** CTCP \(payload) → \(target)"))
            }
        case "silence":
            // Undernet server-side ignore: /silence [nick | +mask | -mask]
            guard !netID.isEmpty else { break }
            if let m = rest.first, !m.isEmpty {
                let mask = (m.hasPrefix("+") || m.hasPrefix("-")) ? m : "+" + (m.contains("!") ? m : "\(m)!*@*")
                Task { await client.sendRaw("SILENCE \(mask)", networkID: netID) }
                appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** SILENCE \(mask)"))
            } else {
                Task { await client.sendRaw("SILENCE", networkID: netID) }   // list current masks
            }
        case "ignore":
            if let n = rest.first, !n.isEmpty {
                if !isIgnored(n) { toggleIgnore(n) }
            } else {
                let list = ignoredNicks.isEmpty ? "(nobody)" : ignoredNicks.joined(separator: ", ")
                appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** Ignoring: \(list)"))
            }
        case "unignore":
            if let n = rest.first, isIgnored(n) { toggleIgnore(n) }
        case "msg", "query":
            if let n = rest.first { openDM(n, message: rest.dropFirst().joined(separator: " ")) }
        case "quit":
            appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server,
                                                  text: "*** You have quit (\(arg.isEmpty ? "Leaving" : arg))"))
        default:
            // Any other slash command (/mode, /kick, /invite, /away, /list, /who,
            // /names, /op, …) is sent through as a raw IRC command.
            guard !netID.isEmpty else { return }
            let verb = cmd.uppercased()
            let raw = arg.isEmpty ? verb : "\(verb) \(arg)"
            Task { await client.sendRaw(raw, networkID: netID) }
            appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: ">> \(raw)"))
        }
    }

    // MARK: Channel / DM management

    func joinChannel(_ name: String) {
        guard let net = selectedNetwork else { return }
        let chan = name.hasPrefix("#") ? name : "#\(name)"
        let id = canonicalConvID("\(net.id)/\(chan)")   // case-insensitive reuse
        if conversations[id] == nil {
            conversations[id] = Conversation(id: id, kind: .channel, name: chan,
                                             members: [Member(nick: net.nick)])
            mutateNetwork(net.id) { if !$0.conversationIDs.contains(id) { $0.conversationIDs.append(id) } }
            Task { await client.join(channel: chan, networkID: net.id) }
        }
        select(id)
    }

    func partCurrent() { remove(selectedID) }

    func remove(_ id: String) {
        guard let c = conversations[id], c.kind != .server, let net = network(for: id) else { return }
        Task { await client.part(conversationID: id) }
        let fallback = net.conversationIDs.first { $0 != id } ?? net.serverConsoleID
        conversations[id] = nil
        mutateNetwork(net.id) { $0.conversationIDs.removeAll { $0 == id } }
        if selectedID == id { selectedID = fallback }
    }

    func openDM(_ nick: String, message: String = "") {
        guard let net = selectedNetwork else { return }
        // Nicks are case-insensitive on IRC — /msg x must reuse the DM with X.
        let id = canonicalConvID("\(net.id)/\(nick)")
        if conversations[id] == nil {
            conversations[id] = Conversation(id: id, kind: .directMessage, name: nick)
            mutateNetwork(net.id) { $0.conversationIDs.append(id) }
        }
        select(id)
        if !message.isEmpty {
            Task { await client.send(text: message, to: id) }
            echoOwn(message, kind: .message, to: id)
        }
    }

    func setTopic(_ topic: String, for id: String) { Task { await client.setTopic(topic, conversationID: id) } }
    func whois(_ nick: String) {
        whoisTargetConvID = selectedID
        Task { await client.whois(nick: nick, conversationID: selectedID) }
    }
    func setMode(_ mode: MemberMode, nick: String) { Task { await client.setMode(mode, nick: nick, conversationID: selectedID) } }

    /// Clicking a nick in chat: open the member panel and spotlight them.
    func revealMember(_ nick: String) {
        memberListVisible = true
        revealedMember = nick
    }
    func kick(_ nick: String) { Task { await client.kick(nick: nick, conversationID: selectedID) } }
    func markRead(_ id: String) {
        mutateConversation(id) { $0.unread = 0; $0.mentions = 0; $0.firstUnreadID = nil }
        updateDockBadge()
    }

    /// Quiet: no counters, no notifications from this conversation.
    func toggleMute(_ id: String) {
        mutateConversation(id) {
            $0.isMuted.toggle()
            if $0.isMuted { $0.unread = 0; $0.mentions = 0; $0.firstUnreadID = nil }
        }
    }

    // MARK: - Ignore (client-side) & SILENCE (server-side)

    func isIgnored(_ nick: String) -> Bool {
        ignoredNicks.contains { $0.caseInsensitiveCompare(nick) == .orderedSame }
    }

    func toggleIgnore(_ nick: String) {
        if isIgnored(nick) {
            ignoredNicks.removeAll { $0.caseInsensitiveCompare(nick) == .orderedSame }
        } else {
            ignoredNicks.append(nick)
        }
        if let data = try? JSONEncoder().encode(ignoredNicks) {
            UserDefaults.standard.set(data, forKey: AppModel.ignoredKey)
        }
        appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server,
            text: isIgnored(nick) ? "*** Now ignoring \(nick) (client-side — /unignore \(nick) to undo)"
                                  : "*** Stopped ignoring \(nick)"))
    }

    /// Server-side ignore on the current network (Undernet SILENCE).
    func silence(_ nick: String) {
        guard let netID = selectedNetwork?.id else { return }
        let mask = "+\(nick)!*@*"
        Task { await client.sendRaw("SILENCE \(mask)", networkID: netID) }
        appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** SILENCE \(mask)"))
    }

    // MARK: Nick completion (for the composer)

    func completions(for token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        let q = token.lowercased()
        // '#'/'&' → complete channel names from the sidebar's channel list.
        if token.hasPrefix("#") || token.hasPrefix("&") {
            let chans = networks.flatMap(\.conversationIDs)
                .compactMap { conversations[$0] }
                .filter { $0.kind == .channel }
                .map(\.name)
            return Array(Set(chans)).filter { $0.lowercased().hasPrefix(q) }.sorted()
        }
        // otherwise nick completion from the active channel only — sorted so
        // Tab-cycling walks the matches in a predictable order
        guard let members = selectedConversation?.members else { return [] }
        return members.map(\.nick).filter { $0.lowercased().hasPrefix(q) }
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    // MARK: - ASCII art

    /// Send a colourful one-liner to the current conversation. `nick` fills the
    /// `%nick%` placeholder (the right-clicked member, or the DM peer).
    func sendArt(_ art: ArtLine, toNick nick: String? = nil) {
        let target = nick ?? (selectedConversation?.kind == .directMessage ? selectedConversation?.name : "")
        let text = ArtCatalog.render(art.template, nick: target ?? "")
        Task { await client.send(text: text, to: selectedID) }
        echoOwn(text, kind: .message, to: selectedID)   // IRC never echoes your own PRIVMSG
    }

    // MARK: - Channel modes (Undernet)

    func networkID(of convID: String) -> String { String(convID.split(separator: "/").first ?? "") }

    /// Set or clear a channel mode, sending the MODE line and tracking it locally.
    func setChannelMode(_ letter: String, enabled: Bool, param: String? = nil, for convID: String) {
        guard let conv = conversations[convID], conv.kind == .channel else { return }
        let netID = networkID(of: convID)
        let sign = enabled ? "+" : "-"
        var line = "MODE \(conv.name) \(sign)\(letter)"
        if let param, !param.isEmpty, enabled || letter == "k" { line += " \(param)" }
        Task { await client.sendRaw(line, networkID: netID) }

        mutateConversation(convID) {
            if enabled {
                $0.activeModes.insert(letter)
                if letter == "l" { $0.modeLimit = Int(param ?? "") }
                if letter == "k" { $0.modeKey = param }
            } else {
                $0.activeModes.remove(letter)
                if letter == "l" { $0.modeLimit = nil }
                if letter == "k" { $0.modeKey = nil }
            }
        }
    }

    // MARK: - X (Channel Service) settings

    private static let xBot = "X@channels.undernet.org"

    func sendXChannelSet(_ option: String, value: String, for convID: String) {
        guard let conv = conversations[convID], conv.kind == .channel else { return }
        let netID = networkID(of: convID)
        Task { await client.sendRaw("PRIVMSG \(AppModel.xBot) :SET \(conv.name) \(option) \(value)", networkID: netID) }
    }

    func sendXUserSet(_ option: String, value: String, networkID: String) {
        Task { await client.sendRaw("PRIVMSG \(AppModel.xBot) :USET \(option) \(value)", networkID: networkID) }
    }

    // MARK: - Parameterised commands (with popups)

    /// Present the popup if there are fields to fill, otherwise send immediately.
    func runCommandPrompt(_ prompt: CommandPrompt) {
        if prompt.fields.isEmpty { sendCommandPrompt(prompt, fields: []) }
        else { commandPrompt = prompt }
    }

    func sendCommandPrompt(_ prompt: CommandPrompt, fields: [CommandField]) {
        commandPrompt = nil
        guard !prompt.networkID.isEmpty, let inner = prompt.build(fields),
              !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let raw = prompt.isX ? "PRIVMSG \(AppModel.xBot) :\(inner)" : inner
        let nid = prompt.networkID
        Task { await client.sendRaw(raw, networkID: nid) }
        appendMessage(to: prompt.echoConvID,
                      Message(id: UUID().uuidString, kind: .server, text: ">> \(prompt.isX ? "X " : "")\(inner)"))
    }

    private func channelCtx(_ convID: String) -> (chan: String, net: String, echo: String)? {
        guard let c = conversations[convID], c.kind == .channel else { return nil }
        return (c.name, networkID(of: convID), convID)
    }
    private func trimmed(_ f: [CommandField], _ i: Int) -> String { f[i].value.trimmingCharacters(in: .whitespaces) }

    // MARK: Normal IRC commands (member, on the selected channel)

    func kickPrompt(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Kick \(nick) from \(c.chan)", networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Reason", prompt: "optional")]) { f in
                let r = self.trimmed(f, 0); return "KICK \(c.chan) \(nick)" + (r.isEmpty ? "" : " :\(r)")
            })
    }
    func banPrompt(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Ban in \(c.chan)",
            note: "Plain channel ban (MODE +b). Use Channel Service → Ban for timed/levelled bans.",
            networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Mask", value: "\(nick)!*@*", required: true)]) { f in
                let m = self.trimmed(f, 0); return m.isEmpty ? nil : "MODE \(c.chan) +b \(m)"
            })
    }

    // MARK: X commands on a member in the selected channel

    private func xSimpleMember(_ verb: String, _ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "", isX: true, networkID: c.net, echoConvID: c.echo, fields: []) { _ in "\(verb) \(c.chan) \(nick)" })
    }
    func xOp(_ n: String) { xSimpleMember("OP", n) }
    func xDeop(_ n: String) { xSimpleMember("DEOP", n) }
    func xVoice(_ n: String) { xSimpleMember("VOICE", n) }
    func xDevoice(_ n: String) { xSimpleMember("DEVOICE", n) }
    func xRemUser(_ n: String) { xSimpleMember("REMUSER", n) }
    func xAccessUser(_ n: String) { xSimpleMember("ACCESS", n) }

    func xKick(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Kick \(nick) from \(c.chan) via X", isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Reason", prompt: "max 128 chars")]) { f in
                let r = self.trimmed(f, 0); return "KICK \(c.chan) \(nick)" + (r.isEmpty ? "" : " \(r)")
            })
    }
    func xBan(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Ban \(nick) in \(c.chan) via X",
            note: "Duration in hours (max 2400). Level 1–74 prevents ops, 75–500 prevents joining. Default 3h / 75.",
            isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [
                CommandField(label: "Mask", value: "\(nick)!*@*", required: true),
                CommandField(label: "Duration (hours)", prompt: "3", kind: .number),
                CommandField(label: "Level", prompt: "75", kind: .number),
                CommandField(label: "Reason", prompt: "optional"),
            ]) { f in
                let mask = self.trimmed(f, 0); guard !mask.isEmpty else { return nil }
                let dur = self.trimmed(f, 1), lvl = self.trimmed(f, 2), reason = self.trimmed(f, 3)
                var parts = ["BAN", c.chan, mask]
                if !dur.isEmpty || !lvl.isEmpty || !reason.isEmpty {
                    parts.append(dur.isEmpty ? "3" : dur)
                    parts.append(lvl.isEmpty ? "75" : lvl)
                    if !reason.isEmpty { parts.append(reason) }
                }
                return parts.joined(separator: " ")
            })
    }
    func xUnban(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Unban in \(c.chan) via X", isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Mask", value: "\(nick)!*@*", required: true)]) { f in
                let m = self.trimmed(f, 0); return m.isEmpty ? nil : "UNBAN \(c.chan) \(m)"
            })
    }
    func xAddUser(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Add \(nick) to \(c.chan) userlist",
            note: "Access level: 1 to your level minus 1.", isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Access level", prompt: "1–499", required: true, kind: .number)]) { f in
                let l = self.trimmed(f, 0); return l.isEmpty ? nil : "ADDUSER \(c.chan) \(nick) \(l)"
            })
    }
    func xSuspend(_ nick: String) {
        guard let c = channelCtx(selectedID) else { return }
        runCommandPrompt(CommandPrompt(title: "Suspend \(nick) in \(c.chan)",
            note: "Duration unit: M=minutes, H=hours, D=days (max 372 days).", isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [
                CommandField(label: "Duration", required: true, kind: .number),
                CommandField(label: "Unit", value: "H", kind: .choice(["M", "H", "D"])),
                CommandField(label: "Level", prompt: "optional", kind: .number),
            ]) { f in
                let d = self.trimmed(f, 0); guard !d.isEmpty else { return nil }
                let u = f[1].value.isEmpty ? "H" : f[1].value
                let l = self.trimmed(f, 2)
                return "SUSPEND \(c.chan) \(nick) \(d) \(u)" + (l.isEmpty ? "" : " \(l)")
            })
    }

    // MARK: X commands on a channel (from the sidebar)

    private func xSimpleChannel(_ verb: String, _ convID: String) {
        guard let c = channelCtx(convID) else { return }
        runCommandPrompt(CommandPrompt(title: "", isX: true, networkID: c.net, echoConvID: c.echo, fields: []) { _ in "\(verb) \(c.chan)" })
    }
    func xChannelInfo(_ id: String) { xSimpleChannel("CHANINFO", id) }
    func xChannelAccess(_ id: String) { xSimpleChannel("ACCESS", id) }
    func xChannelBanlist(_ id: String) { xSimpleChannel("BANLIST", id) }
    func xChannelInvite(_ id: String) { xSimpleChannel("INVITE", id) }
    func xChannelOpMe(_ id: String) { xSimpleChannel("OP", id) }
    func xChannelDeopMe(_ id: String) { xSimpleChannel("DEOP", id) }
    func xChannelClearmode(_ id: String) { xSimpleChannel("CLEARMODE", id) }
    func xChannelTopic(_ convID: String) {
        guard let c = channelCtx(convID) else { return }
        runCommandPrompt(CommandPrompt(title: "Set X topic for \(c.chan)", note: "Max 145 characters.",
            isX: true, networkID: c.net, echoConvID: c.echo,
            fields: [CommandField(label: "Topic", value: conversations[convID]?.topic ?? "", required: true)]) { f in
                let t = f[0].value.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : "TOPIC \(c.chan) \(t)"
            })
    }

    // MARK: - Bans

    func requestChannelList() {
        guard let net = selectedNetwork else { return }
        Task { await client.sendRaw("LIST", networkID: net.id) }
    }

    /// Ask the server for current modes (324) and the ban list (367/368).
    func requestChannelInfo(_ convID: String) {
        guard let conv = conversations[convID], conv.kind == .channel else { return }
        let netID = networkID(of: convID)
        Task {
            await client.sendRaw("MODE \(conv.name)", networkID: netID)
            await client.sendRaw("MODE \(conv.name) +b", networkID: netID)
        }
    }

    func setBan(_ mask: String, enabled: Bool, for convID: String) {
        guard let conv = conversations[convID], conv.kind == .channel,
              !mask.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let netID = networkID(of: convID)
        Task { await client.sendRaw("MODE \(conv.name) \(enabled ? "+" : "-")b \(mask)", networkID: netID) }
        mutateConversation(convID) {
            if enabled { if !$0.bans.contains(mask) { $0.bans.append(mask) } }
            else { $0.bans.removeAll { $0 == mask } }
        }
    }

    /// Ban/unban a nick (as nick!*@*) in the current or given channel.
    func banNick(_ nick: String, for convID: String? = nil) { setBan("\(nick)!*@*", enabled: true, for: convID ?? selectedID) }
    func unbanNick(_ nick: String, for convID: String? = nil) { setBan("\(nick)!*@*", enabled: false, for: convID ?? selectedID) }

    // MARK: - Server configuration: persistence

    func config(for networkID: String) -> ServerConfig? {
        serverConfigs.first { $0.id == networkID }
    }

    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: AppModel.serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            serverConfigs = decoded            // respect saved list, even if empty
        } else {
            serverConfigs = AppModel.seedServerConfigs()
            saveServers()                      // persist so we never reseed again
        }
        let configs = serverConfigs
        Task { await hub.updateConfigs(configs) }
    }

    // MARK: - Custom ASCII art

    private func loadCustomArt() {
        if let data = UserDefaults.standard.data(forKey: AppModel.artKey),
           let decoded = try? JSONDecoder().decode([ArtLine].self, from: data) {
            customArt = decoded
        }
    }

    func saveCustomArt() {
        if let data = try? JSONEncoder().encode(customArt) {
            UserDefaults.standard.set(data, forKey: AppModel.artKey)
        }
    }

    func addCustomArt() {
        customArt.append(ArtLine(name: "New art", template: "%nick%"))
        saveCustomArt()
    }

    func deleteCustomArt(_ id: UUID) {
        customArt.removeAll { $0.id == id }
        saveCustomArt()
    }

    func saveServers() {
        if let data = try? JSONEncoder().encode(serverConfigs) {
            UserDefaults.standard.set(data, forKey: AppModel.serversKey)
        }
    }

    /// Called by the settings editor after any edit: keep runtime networks in
    /// sync with the configs and persist.
    func serversChanged() {
        // Lightweight: only persist + sync the hub. Mutating `networks` here on
        // every keystroke stole first-responder from the settings text fields.
        saveServers()
        let configs = serverConfigs
        Task { await hub.updateConfigs(configs) }
    }

    private func startAutoConnect() {
        for cfg in serverConfigs where cfg.connectOnLaunch {
            ensureNetwork(for: cfg)
            if state(of: cfg.id) != .connected { connect(cfg.id) }
        }
    }

    // MARK: - Server configuration: CRUD

    /// Make sure a runtime `Network` (+ server console) exists for a config and
    /// mirrors its display fields.
    func ensureNetwork(for cfg: ServerConfig) {
        if let i = networks.firstIndex(where: { $0.id == cfg.id }) {
            networks[i].name = cfg.name
            networks[i].server = cfg.host
            if networks[i].state == .disconnected { networks[i].nick = cfg.nick }
        } else {
            var net = Network(id: cfg.id, name: cfg.name, server: cfg.host,
                              nick: cfg.nick, state: .disconnected, isExpanded: true,
                              conversationIDs: [])
            let consoleID = net.serverConsoleID
            net.conversationIDs = [consoleID]
            networks.append(net)
            if conversations[consoleID] == nil {
                conversations[consoleID] = Conversation(id: consoleID, kind: .server, name: cfg.name)
            }
        }
    }

    @discardableResult
    func addServer() -> ServerConfig {
        var cfg = ServerConfig()
        cfg.nick = AppModel.selfNickPlaceholder
        serverConfigs.append(cfg)
        ensureNetwork(for: cfg)
        saveServers()
        return cfg
    }

    func updateServer(_ cfg: ServerConfig) {
        guard let i = serverConfigs.firstIndex(where: { $0.id == cfg.id }) else { return }
        serverConfigs[i] = cfg
        saveServers()
        // NB: do NOT call ensureNetwork here — mutating `networks` on every
        // keystroke re-renders the whole app and steals focus from the editor.
        Task { [serverConfigs] in await hub.updateConfigs(serverConfigs) }
    }

    func deleteServer(_ id: String) {
        serverConfigs.removeAll { $0.id == id }
        networks.removeAll { $0.id == id }
        // Remove every conversation belonging to this network (incl. $server).
        conversations = conversations.filter { networkID(of: $0.key) != id }
        if network(for: selectedID) == nil {
            selectedID = networks.first?.conversationIDs.first ?? networks.first?.serverConsoleID ?? ""
        }
        saveServers()
        Task { [serverConfigs] in await hub.updateConfigs(serverConfigs) }
    }

    // MARK: - On-connect automation

    /// Run the network's perform list (honouring per-command delays), then —
    /// after `joinDelay` — join its auto-join channels.
    private func performOnConnect(_ networkID: String) {
        // Private session: no user modes, no perform, no auto-join — just the
        // secret room.
        if privateModeNetworks.contains(networkID) {
            if let chan = pendingPrivateChannel[networkID] { joinPrivateChannel(chan, networkID: networkID) }
            return
        }
        guard let cfg = config(for: networkID) else { return }
        let nick = networks.first { $0.id == networkID }?.nick ?? cfg.nick

        Task { [weak self] in
            // 1. User modes first (e.g. +x host masking, +w wallops).
            if !cfg.userModes.isEmpty {
                let modes = "+" + cfg.userModes.sorted().joined()
                await self?.client.sendRaw("MODE \(nick) \(modes)", networkID: networkID)
            }
            // 2. Perform commands, in order, each after its delay.
            for cmd in cfg.onConnectCommands {
                let raw = AppModel.rawLine(from: cmd.line, nick: nick)
                guard !raw.isEmpty else { continue }
                if cmd.delay > 0 { try? await Task.sleep(for: .seconds(cmd.delay)) }
                await self?.client.sendRaw(raw, networkID: networkID)
            }
            if cfg.joinDelay > 0 { try? await Task.sleep(for: .seconds(cfg.joinDelay)) }
            // 3. Only after performs: the auto-join list, plus every channel
            // still in the sidebar (an auto-reconnect puts you back where you
            // were).
            guard let self else { return }
            let sidebar = self.networks.first { $0.id == networkID }?.conversationIDs
                .compactMap { self.conversations[$0] }
                .filter { $0.kind == .channel }
                .map(\.name) ?? []
            var seen = Set<String>()
            for channel in cfg.autoJoinChannels + sidebar {
                let norm = (channel.hasPrefix("#") || channel.hasPrefix("&") ? channel : "#\(channel)").lowercased()
                guard seen.insert(norm).inserted else { continue }
                self.joinOnConnect(channel, networkID: networkID)
            }
        }
    }

    // MARK: - Private session

    /// Incognito: (re)connect with a random nick, skip perform/auto-join, join
    /// a random empty channel and set it +s (secret).
    func startPrivateSession(_ networkID: String) {
        let nick = AppModel.randomPrivateNick()
        let chan = AppModel.randomPrivateChannel()
        privateModeNetworks.insert(networkID)
        pendingPrivateChannel[networkID] = chan
        cancelReconnect(networkID)
        mutateNetwork(networkID) { $0.nick = nick }
        appendMessage(to: "\(networkID)/$server",
                      Message(id: UUID().uuidString, kind: .server,
                              text: "*** Private session: nick \(nick), channel \(chan) (+s) — perform & auto-join skipped"))
        Task { [weak self] in
            guard let self else { return }
            if self.state(of: networkID) != .disconnected {
                self.intentionalDisconnect.insert(networkID)   // suppress auto-reconnect for this drop
                await self.hub.disconnect(networkID: networkID)
                try? await Task.sleep(for: .seconds(0.5))
            }
            self.intentionalDisconnect.remove(networkID)
            await self.client.changeNick(nick, networkID: networkID)
            await self.hub.updateConfigs(self.serverConfigs)
            await self.hub.connect(networkID: networkID)
        }
    }

    private func joinPrivateChannel(_ chan: String, networkID: String) {
        joinOnConnect(chan, networkID: networkID)
        let id = "\(networkID)/\(chan)"
        select(id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))   // wait for creator ops
            self?.setChannelMode("s", enabled: true, for: id)
        }
    }

    private static func randomPrivateNick() -> String {
        let a = ["quiet", "gray", "swift", "north", "dusk", "pale", "calm", "low"].randomElement()!
        let b = ["owl", "fox", "elk", "jay", "koi", "wren", "lynx", "hare"].randomElement()!
        return a + b + String(Int.random(in: 10...99))
    }

    private static func randomPrivateChannel() -> String {
        "#" + String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }

    // MARK: - Join-failure recovery (471/473/474/475)

    func retryJoin(_ f: JoinFailure, key: String? = nil) {
        joinFailure = nil
        let raw = (key?.isEmpty == false) ? "JOIN \(f.channel) \(key!)" : "JOIN \(f.channel)"
        Task { await client.sendRaw(raw, networkID: f.networkID) }
        appendMessage(to: "\(f.networkID)/\(f.channel)",
                      Message(id: UUID().uuidString, kind: .server, text: ">> \(raw)"))
    }

    /// Ask X to invite us (473 invite-only), then retry the join.
    func askXInvite(_ f: JoinFailure) {
        joinFailure = nil
        appendMessage(to: "\(f.networkID)/\(f.channel)",
                      Message(id: UUID().uuidString, kind: .server, text: "*** Asking X for an invite to \(f.channel)…"))
        Task { [weak self] in
            await self?.client.sendRaw("PRIVMSG \(AppModel.xBot) :INVITE \(f.channel)", networkID: f.networkID)
            try? await Task.sleep(for: .seconds(2))
            await self?.client.sendRaw("JOIN \(f.channel)", networkID: f.networkID)
        }
    }

    /// Ask X to lift our ban (474), then retry the join.
    func askXUnban(_ f: JoinFailure) {
        let nick = networks.first { $0.id == f.networkID }?.nick ?? ""
        joinFailure = nil
        appendMessage(to: "\(f.networkID)/\(f.channel)",
                      Message(id: UUID().uuidString, kind: .server, text: "*** Asking X to unban \(nick) in \(f.channel)…"))
        Task { [weak self] in
            await self?.client.sendRaw("PRIVMSG \(AppModel.xBot) :UNBAN \(f.channel) \(nick)!*@*", networkID: f.networkID)
            try? await Task.sleep(for: .seconds(2))
            await self?.client.sendRaw("JOIN \(f.channel)", networkID: f.networkID)
        }
    }

    /// Join a channel as part of auto-join without stealing the current selection.
    private func joinOnConnect(_ name: String, networkID: String) {
        let chan = name.hasPrefix("#") || name.hasPrefix("&") ? name : "#\(name)"
        let id = canonicalConvID("\(networkID)/\(chan)")   // case-insensitive reuse
        if conversations[id] == nil {
            conversations[id] = Conversation(id: id, kind: .channel, name: chan, members: [])
            mutateNetwork(networkID) { if !$0.conversationIDs.contains(id) { $0.conversationIDs.append(id) } }
        }
        Task { await client.join(channel: chan, networkID: networkID) }
    }

    /// Translate a perform entry into a raw IRC line. Accepts raw IRC
    /// (`MODE foo +x`), composer-style slash commands (`/msg X :hi`), and
    /// substitutes `%nick%`.
    static func rawLine(from entry: String, nick: String) -> String {
        var s = entry.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%nick%", with: nick)
        guard !s.isEmpty else { return "" }
        guard s.hasPrefix("/") else { return s }   // already a raw IRC line

        s.removeFirst()
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts.first?.lowercased() ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        switch cmd {
        case "msg", "query":
            let sub = rest.split(separator: " ", maxSplits: 1).map(String.init)
            return sub.count == 2 ? "PRIVMSG \(sub[0]) :\(sub[1])" : "PRIVMSG \(rest)"
        case "raw", "quote":
            return rest
        default:
            return s   // "command args" → raw line as-is
        }
    }

    // MARK: - Seed configs (match the demo networks)

    private static func seedServerConfigs() -> [ServerConfig] {
        // A single real, connectable Undernet network. No mock, no auto-join —
        // set your nick, hit Connect.
        [
            ServerConfig(id: "undernet", name: "Undernet",
                         host: "irc.undernet.org", port: 6667, useTLS: false,
                         nick: AppModel.selfNickPlaceholder, realName: "Relay",
                         connectOnLaunch: true)
        ]
    }
}

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

    // Persisted server configurations — the durable records behind `networks`.
    var serverConfigs: [ServerConfig] = []
    private static let serversKey = "relay.serverConfigs.v3"

    // User-defined ASCII art (persisted), shown alongside the built-in catalog.
    var customArt: [ArtLine] = []
    private static let artKey = "relay.customArt.v1"

    init() {
        loadServers()
        buildWorld()
        loadCustomArt()
        Task { await consumeEvents() }
        startAutoConnect()
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
                if was != .connected { performOnConnect(networkID) }
            }

        case let .serverLine(networkID, text):
            if state(of: networkID)?.isBusy == true {
                connectingLog.append(text)
            }
            appendMessage(to: "\(networkID)/$server", Message(id: UUID().uuidString, kind: .server, text: text))

        case let .message(convID, message):
            appendMessage(to: convID, message, incoming: message.nick != selfNick)

        case let .topic(convID, topic):
            mutateConversation(convID) { $0.topic = topic }

        case let .members(convID, members):
            mutateConversation(convID) { $0.members = members }

        case let .memberJoined(convID, member):
            mutateConversation(convID) {
                if !$0.members.contains(where: { $0.nick == member.nick }) { $0.members.append(member) }
            }

        case let .memberLeft(convID, nick, _, _):
            mutateConversation(convID) { $0.members.removeAll { $0.nick == nick } }

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

        case let .nickChanged(networkID, _, to):
            mutateNetwork(networkID) { $0.nick = to }
        }
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
        guard var c = conversations[id] else { return }
        body(&c)
        conversations[id] = c
    }

    private func appendMessage(to convID: String, _ message: Message, incoming: Bool = false) {
        guard var c = conversations[convID] else { return }
        c.messages.append(message)
        if incoming && convID != selectedID {
            c.unread += 1
            if c.firstUnreadID == nil { c.firstUnreadID = message.id }
            let mention = message.text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: selfNick))\\b",
                                             options: [.regularExpression, .caseInsensitive]) != nil
            if mention || c.kind == .directMessage { c.mentions += 1 }
        }
        conversations[convID] = c
    }

    // MARK: Selection

    func select(_ id: String) {
        selectedID = id
        searchOpen = false; searchText = ""
        mutateConversation(id) { $0.unread = 0; $0.mentions = 0; $0.firstUnreadID = nil }
    }

    func selectIndex(_ oneBased: Int) {
        let list = flatConversations
        guard oneBased >= 1, oneBased <= list.count else { return }
        select(list[oneBased - 1].conv.id)
    }

    func toggleNetwork(_ id: String) { mutateNetwork(id) { $0.isExpanded.toggle() } }

    // MARK: Connection

    func connect(_ networkID: String) {
        Task { await hub.updateConfigs(serverConfigs); await hub.connect(networkID: networkID) }
    }
    func disconnect(_ networkID: String) { Task { await hub.disconnect(networkID: networkID) } }

    // MARK: Composer entry point — parse slash commands, else send

    func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.hasPrefix("/") { runCommand(text) }
        else { Task { await client.send(text: text, to: selectedID) } }
    }

    private func runCommand(_ text: String) {
        let parts = text.dropFirst().split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let cmd = parts.first?.lowercased() ?? ""
        let rest = Array(parts.dropFirst())
        let arg = rest.joined(separator: " ")
        let netID = selectedNetwork?.id ?? ""

        switch cmd {
        case "me":    if !arg.isEmpty { Task { await client.sendAction(arg, to: selectedID) } }
        case "join":  if !arg.isEmpty { joinChannel(arg) }
        case "part":  partCurrent()
        case "nick":  if let n = rest.first { Task { await client.changeNick(n, networkID: netID) } }
        case "topic": Task { await client.setTopic(arg, conversationID: selectedID) }
        case "whois": Task { await client.whois(nick: rest.first ?? selfNick, conversationID: selectedID) }
        case "msg", "query":
            if let n = rest.first { openDM(n, message: rest.dropFirst().joined(separator: " ")) }
        case "quit":
            appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server,
                                                  text: "*** You have quit (\(arg.isEmpty ? "Leaving" : arg))"))
        default:
            appendMessage(to: selectedID, Message(id: UUID().uuidString, kind: .server, text: "*** Unknown command: /\(cmd)"))
        }
    }

    // MARK: Channel / DM management

    func joinChannel(_ name: String) {
        guard let net = selectedNetwork else { return }
        let chan = name.hasPrefix("#") ? name : "#\(name)"
        let id = "\(net.id)/\(chan)"
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
        let id = "\(net.id)/\(nick)"
        if conversations[id] == nil {
            conversations[id] = Conversation(id: id, kind: .directMessage, name: nick)
            mutateNetwork(net.id) { $0.conversationIDs.append(id) }
        }
        select(id)
        if !message.isEmpty { Task { await client.send(text: message, to: id) } }
    }

    func setTopic(_ topic: String, for id: String) { Task { await client.setTopic(topic, conversationID: id) } }
    func whois(_ nick: String) { Task { await client.whois(nick: nick, conversationID: selectedID) } }
    func setMode(_ mode: MemberMode, nick: String) { Task { await client.setMode(mode, nick: nick, conversationID: selectedID) } }
    func kick(_ nick: String) { Task { await client.kick(nick: nick, conversationID: selectedID) } }
    func markRead(_ id: String) { mutateConversation(id) { $0.unread = 0; $0.mentions = 0; $0.firstUnreadID = nil } }
    func toggleMute(_ id: String) { mutateConversation(id) { $0.isMuted.toggle() } }

    // MARK: Nick completion (for the composer)

    func completions(for token: String) -> [String] {
        guard !token.isEmpty, let members = selectedConversation?.members else { return [] }
        return members.map(\.nick).filter { $0.lowercased().hasPrefix(token.lowercased()) }
    }

    // MARK: - ASCII art

    /// Send a colourful one-liner to the current conversation. `nick` fills the
    /// `%nick%` placeholder (the right-clicked member, or the DM peer).
    func sendArt(_ art: ArtLine, toNick nick: String? = nil) {
        let target = nick ?? (selectedConversation?.kind == .directMessage ? selectedConversation?.name : "")
        let text = ArtCatalog.render(art.template, nick: target ?? "")
        Task { await client.send(text: text, to: selectedID) }
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
        for cfg in serverConfigs { ensureNetwork(for: cfg) }
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
        ensureNetwork(for: cfg)
        saveServers()
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
            for channel in cfg.autoJoinChannels {
                await self?.joinOnConnect(channel, networkID: networkID)
            }
        }
    }

    /// Join a channel as part of auto-join without stealing the current selection.
    private func joinOnConnect(_ name: String, networkID: String) {
        let chan = name.hasPrefix("#") || name.hasPrefix("&") ? name : "#\(name)"
        let id = "\(networkID)/\(chan)"
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

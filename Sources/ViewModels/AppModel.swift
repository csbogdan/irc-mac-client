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

    // The seam. Replace the right-hand side to go live.
    let client: IRCClient = MockIRCService()

    static let selfNickPlaceholder = "mcimpeanu"

    // MARK: World state
    var networks: [Network] = MockIRCService.seedNetworks()
    var conversations: [String: Conversation] = MockIRCService.seedConversations()
    var selectedID: String = "undernet/#coder-com"

    // MARK: UI state
    var sidebarVisible = true
    var memberListVisible = true
    var quickSwitcherOpen = false
    var searchOpen = false
    var searchText = ""
    var connectingLog: [String] = []

    init() {
        Task { await consumeEvents() }
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
            mutateNetwork(networkID) { $0.state = state }
            if state == .connected { connectingLog = [] }

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

    func connect(_ networkID: String) { Task { await client.connect(networkID: networkID) } }
    func disconnect(_ networkID: String) { Task { await client.disconnect(networkID: networkID) } }

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
}

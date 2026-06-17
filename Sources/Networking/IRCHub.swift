import Foundation

/// Multiplexing transport. Holds one in-memory `MockIRCService` for the curated
/// demo networks plus a `LiveIRCClient` per real network, and merges all their
/// event streams into the single stream `AppModel` consumes. Method calls are
/// routed to the right transport by network. This is what lets a real server
/// connect over a socket while the demo networks stay fully interactive offline.
actor IRCHub: IRCClient {
    nonisolated let events: AsyncStream<IRCEvent>
    private let continuation: AsyncStream<IRCEvent>.Continuation

    private let mock = MockIRCService()
    private var live: [String: LiveIRCClient] = [:]
    private var configs: [String: ServerConfig] = [:]

    init() {
        var cont: AsyncStream<IRCEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
        forward(mock.events)
    }

    /// Keep the hub's view of server configs current (transport choice + creds).
    func updateConfigs(_ list: [ServerConfig]) {
        for c in list { configs[c.id] = c }
    }

    private func forward(_ stream: AsyncStream<IRCEvent>) {
        let cont = continuation
        Task { for await event in stream { cont.yield(event) } }
    }

    /// The transport for a network: the live client if the config opts in (and
    /// it's created lazily), otherwise the shared mock.
    private func transport(for networkID: String) -> any IRCClient {
        guard let cfg = configs[networkID], !cfg.useMockTransport else { return mock }
        if let existing = live[networkID] { return existing }
        let client = LiveIRCClient(config: cfg)
        live[networkID] = client
        forward(client.events)
        return client
    }

    private func net(of conversationID: String) -> String {
        String(conversationID.split(separator: "/").first ?? "")
    }

    // MARK: IRCClient routing

    func connect(networkID: String) async { await transport(for: networkID).connect(networkID: networkID) }
    func disconnect(networkID: String) async { await transport(for: networkID).disconnect(networkID: networkID) }
    func sendRaw(_ line: String, networkID: String) async { await transport(for: networkID).sendRaw(line, networkID: networkID) }
    func join(channel: String, networkID: String) async { await transport(for: networkID).join(channel: channel, networkID: networkID) }
    func changeNick(_ nick: String, networkID: String) async { await transport(for: networkID).changeNick(nick, networkID: networkID) }

    func send(text: String, to conversationID: String) async {
        await transport(for: net(of: conversationID)).send(text: text, to: conversationID)
    }
    func sendAction(_ action: String, to conversationID: String) async {
        await transport(for: net(of: conversationID)).sendAction(action, to: conversationID)
    }
    func part(conversationID: String) async {
        await transport(for: net(of: conversationID)).part(conversationID: conversationID)
    }
    func setTopic(_ topic: String, conversationID: String) async {
        await transport(for: net(of: conversationID)).setTopic(topic, conversationID: conversationID)
    }
    func whois(nick: String, conversationID: String) async {
        await transport(for: net(of: conversationID)).whois(nick: nick, conversationID: conversationID)
    }
    func setMode(_ mode: MemberMode, nick: String, conversationID: String) async {
        await transport(for: net(of: conversationID)).setMode(mode, nick: nick, conversationID: conversationID)
    }
    func kick(nick: String, conversationID: String) async {
        await transport(for: net(of: conversationID)).kick(nick: nick, conversationID: conversationID)
    }
}

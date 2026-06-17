import Foundation

/// Multiplexing transport. Holds one `LiveIRCClient` per network (created lazily
/// on first use from its `ServerConfig`) and merges all their event streams into
/// the single stream `AppModel` consumes. Method calls route to the right client
/// by network.
actor IRCHub: IRCClient {
    nonisolated let events: AsyncStream<IRCEvent>
    private let continuation: AsyncStream<IRCEvent>.Continuation

    private var live: [String: LiveIRCClient] = [:]
    private var configs: [String: ServerConfig] = [:]

    init() {
        var cont: AsyncStream<IRCEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    /// Keep the hub's view of server configs current (creds, host, …).
    func updateConfigs(_ list: [ServerConfig]) {
        for c in list { configs[c.id] = c }
    }

    private func forward(_ stream: AsyncStream<IRCEvent>) {
        let cont = continuation
        Task { for await event in stream { cont.yield(event) } }
    }

    /// The live client for a network, created lazily from its config.
    private func transport(for networkID: String) -> any IRCClient {
        if let existing = live[networkID] { return existing }
        let cfg = configs[networkID] ?? ServerConfig(id: networkID)
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

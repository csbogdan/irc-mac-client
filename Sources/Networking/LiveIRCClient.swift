import Foundation
import Network

/// Live IRC client over a raw TLS TCP socket using Network.framework.
///
/// Transport, framing and protocol parsing live inside this dedicated actor so
/// they never touch the main actor. It emits the same `IRCEvent` stream the
/// `MockIRCService` does, so the view model cannot tell them apart.
///
/// NOTE: This is the production transport. The app currently boots with
/// `MockIRCService` (see `AppModel.init`). Swapping is the one-line change:
///
///     let client: IRCClient = LiveIRCClient(host: "irc.undernet.org", port: 6697)
///
actor LiveIRCClient: IRCClient {

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let useTLS: Bool
    private let networkID: String
    private var connection: NWConnection?
    private var buffer = Data()
    private var nick: String
    private let baseNick: String
    private let altNick: String
    private var nickAttempt = 0
    private var registered = false
    private var namesBuffer: [String: [Member]] = [:]   // channel → names accumulated across 353s

    /// Parse a NAMES token like "@nick", "+nick", "~nick" into a Member with mode.
    private static func parseMember(_ token: Substring) -> Member {
        var t = token
        var mode: MemberMode = .regular
        loop: while let f = t.first {
            switch f {
            case "~", "&", "@": mode = .op            // owner/admin/op → op glyph
            case "%", "+": if mode == .regular { mode = .voice }
            default: break loop
            }
            t = t.dropFirst()
        }
        return Member(nick: String(t), mode: mode)
    }

    // Identity / auth, from the server config.
    private let username: String
    private let realName: String
    private let serverPassword: String
    private let saslEnabled: Bool
    private let saslAccount: String
    private let saslPassword: String

    private var continuation: AsyncStream<IRCEvent>.Continuation?
    nonisolated let events: AsyncStream<IRCEvent>

    init(config: ServerConfig) {
        self.networkID = config.id
        self.host = NWEndpoint.Host(config.host)
        self.port = NWEndpoint.Port(rawValue: config.port > 0 ? UInt16(config.port) : 6697) ?? 6697
        self.useTLS = config.useTLS
        self.nick = config.nick
        self.baseNick = config.nick
        self.altNick = config.altNick
        self.username = config.effectiveUsername
        self.realName = config.realName.isEmpty ? config.nick : config.realName
        self.serverPassword = config.serverPassword
        self.saslEnabled = config.saslEnabled && !config.saslAccount.isEmpty
        self.saslAccount = config.saslAccount
        self.saslPassword = config.saslPassword
        var cont: AsyncStream<IRCEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    // MARK: Connection lifecycle

    func connect(networkID: String) async {
        emit(.stateChanged(networkID: networkID, .connecting))
        emit(.serverLine(networkID: networkID, text: "*** Connecting to \(host):\(port) (\(useTLS ? "TLS" : "plain"))…"))

        let params: NWParameters = useTLS ? NWParameters(tls: .init(), tcp: .init())
                                          : NWParameters(tls: nil, tcp: .init())
        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleState(state) }
        }
        receiveLoop(on: conn)
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            // Socket/TLS up — begin registration with CAP negotiation.
            emit(.stateChanged(networkID: networkID, .registering))
            emit(.serverLine(networkID: networkID, text: "*** Socket ready — registering as \(nick)…"))
            if !serverPassword.isEmpty {
                rawSend(IRCParser.serialize(command: "PASS", params: [serverPassword]))
            }
            rawSend(IRCParser.serialize(command: "CAP", params: ["LS", "302"]))
            rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
            rawSend(IRCParser.serialize(command: "USER", params: [username, "0", "*", realName]))
        case .failed(let error):
            emit(.serverLine(networkID: networkID, text: "*** Connection failed: \(error.localizedDescription)"))
            emit(.stateChanged(networkID: networkID, .disconnected))
        case .cancelled:
            emit(.stateChanged(networkID: networkID, .disconnected))
        default:
            break
        }
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { await self.ingest(data) }
            }
            if error == nil && !isComplete {
                Task { await self.continueReceive() }
            } else {
                Task { await self.emitDisconnect() }
            }
        }
    }

    private func continueReceive() { if let c = connection { receiveLoop(on: c) } }
    private func emitDisconnect() { emit(.stateChanged(networkID: networkID, .disconnected)) }

    // MARK: Framing — split on CRLF, parse each line

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0D, 0x0A])) {  // \r\n
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                handle(line)
            }
        }
    }

    private func handle(_ line: String) {
        guard let msg = IRCParser.parse(line) else { return }

        // Always answer PING to stay connected.
        if msg.command == "PING" {
            rawSend(IRCParser.serialize(command: "PONG", params: msg.params))
            return
        }

        switch msg.command {
        case "CAP":          handleCAP(msg)
        case "AUTHENTICATE": handleAuthenticate(msg)
        case "900":          emit(.serverLine(networkID: networkID, text: msg.trailing ?? "Logged in"))
        case "903":          rawSend(IRCParser.serialize(command: "CAP", params: ["END"]))   // SASL ok
        case "902", "904", "905", "906", "907", "908":
            emit(.serverLine(networkID: networkID, text: "*** SASL: \(msg.trailing ?? "authentication failed")"))
            rawSend(IRCParser.serialize(command: "CAP", params: ["END"]))
        case "433", "436", "437":   // nick in use / collision / unavailable
            guard !registered else { break }
            let old = nick
            nick = nextNick()
            emit(.serverLine(networkID: networkID, text: "*** Nick \"\(old)\" is taken — trying \"\(nick)\""))
            rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
            emit(.nickChanged(networkID: networkID, from: old, to: nick))
        case "432":                 // erroneous nickname
            guard !registered else { break }
            let old = nick
            nick = "Relay\(abs(old.hashValue) % 100000)"
            rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
            emit(.nickChanged(networkID: networkID, from: old, to: nick))
        case "001":
            registered = true
            emit(.stateChanged(networkID: networkID, .connected))
            emit(.serverLine(networkID: networkID, text: msg.trailing ?? "Welcome"))
        case "PRIVMSG":
            guard let target = msg.params.first, let body = msg.trailing else { break }
            let convID = "\(networkID)/\(target.hasPrefix("#") ? target : (msg.sourceNick ?? target))"
            // CTCP request (e.g. VERSION, PING) — answer via NOTICE, don't render.
            if body.hasPrefix("\u{01}"), !body.hasPrefix("\u{01}ACTION "), let from = msg.sourceNick {
                answerCTCP(body: body, from: from)
                break
            }
            // CTCP ACTION → /me
            if body.hasPrefix("\u{01}ACTION ") {
                let action = body.dropFirst(8).dropLast()
                emit(.message(conversationID: convID,
                              Message(id: UUID().uuidString, kind: .action,
                                      nick: msg.sourceNick ?? "", text: String(action))))
            } else {
                emit(.message(conversationID: convID,
                              Message(id: UUID().uuidString, kind: .message,
                                      nick: msg.sourceNick ?? "", text: body)))
            }
        case "NOTICE":
            guard let target = msg.params.first, let body = msg.trailing else { break }
            // Channel notice → channel; user/service notice → DM with the sender;
            // server notice (no nick source) → server console.
            let convID: String
            if target.hasPrefix("#") || target.hasPrefix("&") {
                convID = "\(networkID)/\(target)"
            } else if let from = msg.sourceNick, !from.isEmpty {
                convID = "\(networkID)/\(from)"
            } else {
                convID = "\(networkID)/$server"
            }
            emit(.message(conversationID: convID,
                          Message(id: UUID().uuidString, kind: .notice,
                                  nick: msg.sourceNick ?? "*", text: body)))
        case "JOIN":
            if let chan = msg.params.first, let nick = msg.sourceNick {
                emit(.memberJoined(conversationID: "\(networkID)/\(chan)",
                                   Member(nick: nick)))
            }
        case "PART":
            if let nick = msg.sourceNick, let chan = msg.params.first {
                emit(.memberLeft(conversationID: "\(networkID)/\(chan)",
                                 nick: nick, reason: msg.trailing ?? "", kind: .part))
            }
        case "QUIT":
            if let nick = msg.sourceNick {
                emit(.userQuit(networkID: networkID, nick: nick, reason: msg.trailing ?? "Quit"))
            }
        case "KICK":
            // KICK <channel> <nick> :<reason>
            if msg.params.count >= 2 {
                let by = msg.sourceNick ?? "?"
                let reason = msg.trailing ?? ""
                emit(.memberLeft(conversationID: "\(networkID)/\(msg.params[0])",
                                 nick: msg.params[1],
                                 reason: "was kicked by \(by)\(reason.isEmpty ? "" : " (\(reason))")",
                                 kind: .part))
            }
        case "TOPIC", "332":
            if let chan = msg.params.dropFirst(msg.command == "332" ? 1 : 0).first,
               let topic = msg.trailing {
                emit(.topic(conversationID: "\(networkID)/\(chan)", topic))
            }
        case "353":   // RPL_NAMREPLY — names in a channel
            // params: <me> <symbol> <#channel> :<prefixed names>
            if msg.params.count >= 3 {
                let chan = msg.params[2]
                let members = (msg.trailing ?? "").split(separator: " ").map { Self.parseMember($0) }
                namesBuffer[chan, default: []].append(contentsOf: members)
            }
        case "366":   // RPL_ENDOFNAMES
            if let chan = msg.params.dropFirst().first {
                emit(.members(conversationID: "\(networkID)/\(chan)", namesBuffer[chan] ?? []))
                namesBuffer[chan] = nil
            }
        case "MODE":
            handleMode(msg)
        case "324":   // RPL_CHANNELMODEIS — current modes on join/query
            handleChannelModeIs(msg)
        case "NICK":
            if let from = msg.sourceNick, let to = msg.trailing {
                emit(.nickChanged(networkID: networkID, from: from, to: to))
            }
        default:
            // Numerics and the rest land in the server console.
            if Int(msg.command) != nil, let t = msg.trailing {
                emit(.serverLine(networkID: networkID, text: t))
            }
        }
    }

    /// Next nick to try on a collision: the configured alternate first, then the
    /// base nick with growing underscores, then a numeric suffix.
    private func nextNick() -> String {
        nickAttempt += 1
        if nickAttempt == 1, !altNick.isEmpty, altNick != baseNick { return altNick }
        if nickAttempt <= 3 { return baseNick + String(repeating: "_", count: nickAttempt) }
        return baseNick + "\(nickAttempt)"
    }

    // MARK: CAP / SASL negotiation

    private func handleCAP(_ msg: IRCMessage) {
        // :server CAP * <subcommand> :<caps>
        let sub = msg.params.count >= 2 ? msg.params[1].uppercased() : ""
        let caps = msg.trailing ?? ""
        switch sub {
        case "LS":
            if saslEnabled, caps.split(separator: " ").contains("sasl") {
                rawSend(IRCParser.serialize(command: "CAP", params: ["REQ", "sasl"]))
            } else {
                rawSend(IRCParser.serialize(command: "CAP", params: ["END"]))
            }
        case "ACK":
            if caps.contains("sasl") {
                rawSend(IRCParser.serialize(command: "AUTHENTICATE", params: ["PLAIN"]))
            } else {
                rawSend(IRCParser.serialize(command: "CAP", params: ["END"]))
            }
        case "NAK":
            rawSend(IRCParser.serialize(command: "CAP", params: ["END"]))
        default:
            break
        }
    }

    private func handleAuthenticate(_ msg: IRCMessage) {
        guard msg.params.first == "+" else { return }
        // SASL PLAIN payload: authzid \0 authcid \0 passwd  (authzid empty)
        let raw = "\u{0}\(saslAccount)\u{0}\(saslPassword)"
        let payload = Data(raw.utf8).base64EncodedString()
        rawSend(IRCParser.serialize(command: "AUTHENTICATE", params: [payload]))
    }

    // MARK: MODE parsing

    /// Modes whose parameter is consumed from the argument list.
    private static let paramOnSet: Set<Character> = ["o", "v", "b", "k", "l"]
    private static let paramOnUnset: Set<Character> = ["o", "v", "b", "k"]

    private func handleMode(_ msg: IRCMessage) {
        guard let target = msg.params.first else { return }
        // User mode (target is a nick, not a channel) — not tracked in UI yet.
        guard target.hasPrefix("#") || target.hasPrefix("&") else { return }
        let convID = "\(networkID)/\(target)"
        let tokens = Array(msg.params.dropFirst())
        guard let modeString = tokens.first else { return }
        var args = Array(tokens.dropFirst())

        var adding = true
        for ch in modeString {
            switch ch {
            case "+": adding = true
            case "-": adding = false
            default:
                let takesArg = adding ? LiveIRCClient.paramOnSet.contains(ch)
                                      : LiveIRCClient.paramOnUnset.contains(ch)
                let arg = takesArg && !args.isEmpty ? args.removeFirst() : nil
                applyMode(ch, adding: adding, arg: arg, convID: convID)
            }
        }
    }

    private func applyMode(_ ch: Character, adding: Bool, arg: String?, convID: String) {
        switch ch {
        case "o":
            if let nick = arg { emit(.modeChanged(conversationID: convID, nick: nick, mode: adding ? .op : .regular)) }
        case "v":
            if let nick = arg { emit(.modeChanged(conversationID: convID, nick: nick, mode: adding ? .voice : .regular)) }
        case "b":
            break   // ban list — not modelled in the member list
        default:
            emit(.channelModeChanged(conversationID: convID, letter: String(ch), enabled: adding, arg: arg))
        }
    }

    /// RPL_CHANNELMODEIS: <client> <#channel> <modestring> [args…]
    private func handleChannelModeIs(_ msg: IRCMessage) {
        guard msg.params.count >= 3 else { return }
        let channel = msg.params[1]
        let convID = "\(networkID)/\(channel)"
        var args = Array(msg.params.dropFirst(3))
        for ch in msg.params[2] where ch != "+" {
            let takesArg = LiveIRCClient.paramOnSet.contains(ch)
            let arg = takesArg && !args.isEmpty ? args.removeFirst() : nil
            applyMode(ch, adding: true, arg: arg, convID: convID)
        }
    }

    // MARK: CTCP

    private var ctcpSeed = 0

    private func answerCTCP(body: String, from nick: String) {
        let inner = body.trimmingCharacters(in: CharacterSet(charactersIn: "\u{01}"))
        let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        ctcpSeed &+= 1
        guard let reply = CTCP.reply(to: cmd, argument: arg, seed: ctcpSeed) else { return }
        rawSend(IRCParser.serialize(command: "NOTICE",
                                    params: [nick, "\u{01}\(cmd.uppercased()) \(reply)\u{01}"]))
        emit(.serverLine(networkID: networkID, text: "[CTCP] \(cmd.uppercased()) from \(nick) → \(reply)"))
    }

    // MARK: Sending

    private func rawSend(_ s: String) {
        connection?.send(content: s.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    func disconnect(networkID: String) async {
        connection?.cancel()
        connection = nil
        emit(.stateChanged(networkID: networkID, .disconnected))
    }

    func sendRaw(_ line: String, networkID: String) async {
        rawSend(line.hasSuffix("\r\n") ? line : line + "\r\n")
    }

    func send(text: String, to conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        rawSend(IRCParser.serialize(command: "PRIVMSG", params: [target, text]))
    }
    func sendAction(_ action: String, to conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        rawSend(IRCParser.serialize(command: "PRIVMSG", params: [target, "\u{01}ACTION \(action)\u{01}"]))
    }
    func join(channel: String, networkID: String) async {
        rawSend(IRCParser.serialize(command: "JOIN", params: [channel]))
    }
    func part(conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        rawSend(IRCParser.serialize(command: "PART", params: [target]))
    }
    func setTopic(_ topic: String, conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        rawSend(IRCParser.serialize(command: "TOPIC", params: [target, topic]))
    }
    func changeNick(_ nick: String, networkID: String) async {
        self.nick = nick
        rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
    }
    func whois(nick: String, conversationID: String) async {
        rawSend(IRCParser.serialize(command: "WHOIS", params: [nick]))
    }
    func setMode(_ mode: MemberMode, nick: String, conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        let flag = mode == .op ? "+o" : "+v"
        rawSend(IRCParser.serialize(command: "MODE", params: [target, flag, nick]))
    }
    func kick(nick: String, conversationID: String) async {
        let target = String(conversationID.split(separator: "/").last ?? "")
        rawSend(IRCParser.serialize(command: "KICK", params: [target, nick]))
    }

    // MARK: Emit helper
    private func emit(_ event: IRCEvent) { continuation?.yield(event) }
}

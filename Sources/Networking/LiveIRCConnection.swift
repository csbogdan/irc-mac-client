import Foundation
import Network

/// Live IRC client over `Network.framework`. Functional skeleton: it connects,
/// registers (NICK/USER), answers PING, and maps the common numerics/commands to
/// `IRCEvent`s. SASL, IRCv3 CAP negotiation, and richer numerics are TODO.
actor LiveIRCConnection: IRCConnection {
    nonisolated let events: AsyncStream<IRCEvent>
    private nonisolated let continuation: AsyncStream<IRCEvent>.Continuation
    private let config: ServerConfig
    private let connection: NWConnection
    private var buffer = Data()
    private var memberAccumulator: [String: [Member]] = [:]   // channel → names so far

    init(config: ServerConfig) {
        self.config = config
        let (stream, cont) = AsyncStream<IRCEvent>.makeStream()
        self.events = stream
        self.continuation = cont

        let params: NWParameters = config.useTLS ? .tls : .tcp
        let port = NWEndpoint.Port(rawValue: config.port) ?? 6697
        self.connection = NWConnection(host: .init(config.host), port: port, using: params)
    }

    func start() async {
        emit(.stateChanged(.connecting))
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handle(state: state) }
        }
        receiveLoop()
        connection.start(queue: .global(qos: .userInitiated))
    }

    func send(line: String) async {
        sendRaw(line)
    }

    func stop() async {
        connection.cancel()
        emit(.stateChanged(.disconnected))
        continuation.finish()
    }

    // MARK: - Connection lifecycle

    private func handle(state: NWConnection.State) {
        switch state {
        case .ready:
            emit(.stateChanged(.registering))
            sendRaw("NICK \(config.nick)")
            sendRaw("USER \(config.nick) 0 * :\(config.realName)")
        case .failed(let error):
            emit(.stateChanged(.failed(error.localizedDescription)))
            continuation.finish()
        case .cancelled:
            continuation.finish()
        default:
            break
        }
    }

    private nonisolated func emit(_ event: IRCEvent) {
        continuation.yield(event)
    }

    private func sendRaw(_ line: String) {
        let payload = Data((line + "\r\n").utf8)
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    // MARK: - Receive + parse

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { await self.ingest(data) }
            }
            if error == nil && !isComplete {
                Task { await self.receiveLoop() }
            }
        }
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            guard !line.isEmpty else { continue }
            route(line)
        }
    }

    private func route(_ line: String) {
        guard let msg = IRCProtocolParser.parse(line) else { return }
        switch msg.command {
        case "PING":
            sendRaw("PONG :\(msg.params.first ?? "")")
        case "001":
            emit(.stateChanged(.connected))
            for channel in config.autoJoin { sendRaw("JOIN \(channel)") }
        case "PRIVMSG":
            let target = msg.params.first ?? ""
            let body = msg.params.last ?? ""
            let sender = msg.senderNick ?? "server"
            let mentions = body.localizedCaseInsensitiveContains(config.nick)
            if body.hasPrefix("\u{01}ACTION") {
                let action = body.dropFirst(7).dropLast().trimmingCharacters(in: .whitespaces)
                let chat = ChatLine(kind: .action, sender: sender, text: action, isMention: mentions)
                deliver(target: target, sender: sender, line: chat)
            } else {
                let chat = ChatLine(kind: .message, sender: sender, text: body, isMention: mentions)
                deliver(target: target, sender: sender, line: chat)
            }
        case "NOTICE":
            let target = msg.params.first ?? ""
            emit(.line(channel: target, ChatLine(kind: .notice, sender: msg.senderNick ?? "server", text: msg.params.last ?? "")))
        case "JOIN":
            let name = msg.params.first ?? ""
            if msg.senderNick == config.nick {
                emit(.channelJoined(name: name, topic: ""))
            } else {
                emit(.line(channel: name, ChatLine(kind: .join, sender: msg.senderNick ?? "?", text: "\(msg.senderNick ?? "?") joined")))
            }
        case "PART":
            let name = msg.params.first ?? ""
            emit(.line(channel: name, ChatLine(kind: .part, sender: msg.senderNick ?? "?", text: "\(msg.senderNick ?? "?") left")))
        case "332":  // RPL_TOPIC
            if msg.params.count >= 3 { emit(.topic(channel: msg.params[1], msg.params[2])) }
        case "353":  // RPL_NAMREPLY
            if let channel = msg.params.dropFirst(2).first {
                let names = (msg.params.last ?? "").split(separator: " ").map { token -> Member in
                    var t = token
                    var prefix: Member.Prefix = .none
                    if t.first == "@" { prefix = .op; t = t.dropFirst() }
                    else if t.first == "%" { prefix = .halfOp; t = t.dropFirst() }
                    else if t.first == "+" { prefix = .voice; t = t.dropFirst() }
                    return Member(nick: String(t), prefix: prefix)
                }
                memberAccumulator[channel, default: []].append(contentsOf: names)
            }
        case "366":  // RPL_ENDOFNAMES
            if let channel = msg.params.dropFirst(1).first {
                emit(.members(channel: String(channel), memberAccumulator[String(channel)] ?? []))
                memberAccumulator[String(channel)] = nil
            }
        default:
            break
        }
    }

    private func deliver(target: String, sender: String, line: ChatLine) {
        if target.hasPrefix("#") || target.hasPrefix("&") {
            emit(.line(channel: target, line))
        } else {
            emit(.privateMessage(peer: sender, line))
        }
    }
}

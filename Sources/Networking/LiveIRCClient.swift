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
    /// Nick held before an optimistic /nick, for rollback when it is refused.
    private var previousNick: String?
    /// Nick set deliberately while disconnected (private session) — survives
    /// into the next registration.
    private var nickOverride: String?
    /// The configured nick, kept current by the hub as settings change.
    private var configNick: String
    private var registered = false
    private var namesBuffer: [String: [Member]] = [:]   // channel → names accumulated across 353s
    private var banBuffer: [String: [String]] = [:]     // channel → ban masks accumulated across 367s
    private var listBuffer: [ChannelListItem] = []      // accumulated /list results

    /// Format a WHOIS numeric into a human-readable line.
    private func formatWhois(_ msg: IRCMessage) -> String {
        let p = msg.params
        let who = p.count > 1 ? p[1] : ""
        switch msg.command {
        case "311": // <me> <nick> <user> <host> * :<real>
            let user = p.count > 2 ? p[2] : "", host = p.count > 3 ? p[3] : ""
            return "\(who) is \(user)@\(host) (\(msg.trailing ?? ""))"
        case "312": return "\(who) on \(p.count > 2 ? p[2] : "") (\(msg.trailing ?? ""))"
        case "313": return "\(who) is an IRC operator"
        case "317": // <me> <nick> <idle> <signon> :seconds idle, signon time
            var line = "\(who) has been idle \(Self.duration(seconds: Int(p.count > 2 ? p[2] : "") ?? 0))"
            if p.count > 3, let ts = TimeInterval(p[3]), ts > 0 {
                let f = DateFormatter()
                f.dateFormat = "MMM d, HH:mm"
                line += " — signed on \(f.string(from: Date(timeIntervalSince1970: ts)))"
            }
            return line
        case "319": return "\(who) on channels: \(msg.trailing ?? "")"
        case "330": return "\(who) \(msg.trailing ?? "is logged in as") \(p.count > 2 ? p[2] : "")"
        case "338": return "\(who) actual host: \(p.dropFirst(2).joined(separator: " ")) \(msg.trailing ?? "")"
        case "301": return "\(who) is away: \(msg.trailing ?? "")"
        case "671": return "\(who) is using a secure connection"
        case "318": return "End of /WHOIS for \(who)"
        default:    return msg.trailing ?? msg.params.dropFirst().joined(separator: " ")
        }
    }

    /// 62 → "1m 2s", 8040 → "2h 14m", …
    private static func duration(seconds: Int) -> String {
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

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
        self.configNick = config.nick
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
        // Reset per-session state — this instance is reused across reconnects.
        closing = false
        registered = false
        nickAttempt = 0
        // Start every session from the nick we're meant to use: an explicit
        // pre-connect override (private session) wins, otherwise the current
        // configured nick — never a fallback or refused nick left over from the
        // last session.
        nick = nickOverride ?? configNick
        nickOverride = nil
        previousNick = nil
        buffer.removeAll()
        sendQueue.removeAll()
        sendPump?.cancel()
        sendTimer = .distantPast
        namesBuffer.removeAll(); banBuffer.removeAll(); listBuffer.removeAll()
        isupport.removeAll(); chanTypes = "#&"

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
            // Drop the handle too — `connection != nil` is our "do we have a
            // socket" test, and a stale one sends a private session's nick
            // into the void instead of registering with it.
            connection = nil
            emit(.serverLine(networkID: networkID, text: "*** Connection failed: \(error.localizedDescription)"))
            emit(.stateChanged(networkID: networkID, .disconnected))
        case .cancelled:
            connection = nil
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
    private func emitDisconnect() {
        connection = nil
        emit(.stateChanged(networkID: networkID, .disconnected))
    }

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
            // Post-registration these are refusals of a /nick we asked for
            // (or ircu's 437 "banned on channel"): report, keep the old nick.
            guard !registered else {
                // A /nick we asked for was refused — put our own copy back.
                if let prev = previousNick {
                    nick = prev
                    previousNick = nil
                }
                emitNumeric(msg)
                break
            }
            let old = nick
            nick = nextNick()
            emit(.serverLine(networkID: networkID, text: "*** Nick \"\(old)\" is taken — trying \"\(nick)\""))
            rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
            emit(.nickChanged(networkID: networkID, from: old, to: nick))
        case "432", "438":          // erroneous nickname / nick change too fast
            guard !registered else {
                if let prev = previousNick { nick = prev; previousNick = nil }
                emitNumeric(msg)
                break
            }
            guard msg.command == "432" else { break }
            let old = nick
            nick = "Relay\(abs(old.hashValue) % 100000)"
            rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
            emit(.nickChanged(networkID: networkID, from: old, to: nick))
        case "001":
            registered = true
            previousNick = nil
            // RPL_WELCOME's first param is the nick we actually got. Emit it
            // BEFORE .connected so the perform list expands %nick% correctly.
            if let confirmed = msg.params.first, !confirmed.isEmpty, confirmed != "*" {
                nick = confirmed
                emit(.selfNickConfirmed(networkID: networkID, nick: confirmed))
            }
            emit(.stateChanged(networkID: networkID, .connected))
            emit(.serverLine(networkID: networkID, text: msg.trailing ?? "Welcome"))
        case "PRIVMSG":
            guard let target = msg.params.first, let body = msg.trailing else { break }
            let convID = "\(networkID)/\(isChannel(target) ? target : (msg.sourceNick ?? target))"
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
            if isChannel(target) {
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
                // ":nick PART #chan" has no reason — params.last is the channel
                // itself, so only treat a SECOND param as the part message.
                let reason = msg.params.count > 1 ? (msg.params.last ?? "") : ""
                emit(.memberLeft(conversationID: "\(networkID)/\(chan)",
                                 nick: nick, reason: reason.isEmpty ? "left" : "left (\(reason))",
                                 kind: .part))
            }
        case "QUIT":
            if let nick = msg.sourceNick {
                let reason = msg.params.last ?? ""
                emit(.userQuit(networkID: networkID, nick: nick,
                               reason: reason.isEmpty ? "quit" : "quit (\(reason))"))
            }
        case "KICK":
            // KICK <channel> <nick> :<reason>
            if msg.params.count >= 2 {
                let by = msg.sourceNick ?? "?"
                // ":by KICK #chan nick" may carry no reason — params.last is
                // then the kicked nick, not a message.
                let reason = msg.params.count > 2 ? (msg.params.last ?? "") : ""
                let who = msg.params[1]
                emit(.memberLeft(conversationID: "\(networkID)/\(msg.params[0])",
                                 nick: who,
                                 reason: "*** \(who) was kicked by \(by)\(reason.isEmpty ? "" : " (\(reason))")",
                                 kind: .kick))
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
        case "367":   // RPL_BANLIST: <me> <#chan> <mask> [setter] [time]
            if msg.params.count >= 3 {
                banBuffer[msg.params[1], default: []].append(msg.params[2])
            }
        case "368":   // RPL_ENDOFBANLIST
            if let chan = msg.params.dropFirst().first {
                emit(.banList(conversationID: "\(networkID)/\(chan)", masks: banBuffer[chan] ?? []))
                banBuffer[chan] = nil
            }
        case "321": listBuffer = []                       // RPL_LISTSTART
        case "322":                                        // RPL_LIST: <me> <#chan> <count> :<topic>
            if msg.params.count >= 3 {
                listBuffer.append(ChannelListItem(name: msg.params[1],
                                                  users: Int(msg.params[2]) ?? 0,
                                                  topic: msg.trailing ?? ""))
            }
        case "323":                                        // RPL_LISTEND
            emit(.channelList(networkID: networkID, items: listBuffer))
            listBuffer = []
        case "311", "312", "313", "317", "318", "319", "330", "338", "301", "671", "276", "275":
            emit(.whois(networkID: networkID, text: formatWhois(msg)))
        case "MODE":
            handleMode(msg)
        case "324":   // RPL_CHANNELMODEIS — current modes on join/query
            handleChannelModeIs(msg)
        case "NICK":
            // ircu sends the new nick as a plain param (":old NICK new"), other
            // servers as a trailing (":old NICK :new") — accept both.
            if let from = msg.sourceNick, let to = msg.params.last, !to.isEmpty {
                // Our own nick changed (or was changed for us by the server) —
                // keep the transport's copy in step or every later self-check
                // (echo, highlight, member rename) compares against a dead nick.
                // Match on `to` as well: changeNick already moved `nick` to the
                // new value optimistically, so the echo's `from` no longer
                // matches it — without this the rollback slot is never cleared
                // and a later refusal reverts us to a dead nick.
                if from.caseInsensitiveCompare(nick) == .orderedSame
                    || to.caseInsensitiveCompare(nick) == .orderedSame {
                    nick = to
                    previousNick = nil          // accepted — nothing to roll back
                }
                emit(.nickChanged(networkID: networkID, from: from, to: to))
            }
        case "INVITE":
            // :nick INVITE you :#channel
            if let from = msg.sourceNick {
                let chan = msg.trailing ?? msg.params.last ?? ""
                emit(.serverLine(networkID: networkID, text: "*** \(from) invites you to \(chan)  (type /join \(chan))"))
            }
        case "PONG", "PING":
            break   // keepalive — never shown
        case "396":   // RPL_HOSTHIDDEN: <me> <host> :is now your hidden host
            if msg.params.count >= 2 {
                emit(.serverLine(networkID: networkID, text: "\(msg.params[1]) — \(msg.trailing ?? "is now your hidden host")"))
            }
        case "471", "473", "474", "475":
            // <me> <#channel> :reason — join refused (full / invite-only /
            // banned / needs key). Surfaced as a distinct event for proper UX.
            if msg.params.count >= 2 {
                emit(.joinFailed(networkID: networkID, channel: msg.params[1],
                                 code: Int(msg.command) ?? 0, reason: msg.trailing ?? ""))
            }
        case "329", "333":
            break   // channel creation / topic-set timestamps — noise

        // ---- Registration / server info ----
        case "005":   // RPL_ISUPPORT — learn this server's capabilities
            handleISupport(msg)
        case "002", "003", "004", "010", "250", "251", "252", "253", "254",
             "255", "256", "257", "258", "259", "265", "266",
             "371", "372", "374", "375", "376", "422":
            emit(.serverLine(networkID: networkID, text: msg.params.last ?? ""))

        // ---- Away ----
        case "305", "306":
            emit(.serverLine(networkID: networkID, text: msg.params.last ?? ""))
        case "AWAY":
            // IRCv3 away-notify: ":nick AWAY [:reason]"
            if let who = msg.sourceNick {
                let reason = msg.params.last ?? ""
                emit(.serverLine(networkID: networkID,
                                 text: reason.isEmpty ? "*** \(who) is back"
                                                      : "*** \(who) is away: \(reason)"))
            }

        // ---- WHO / WHOWAS ----
        case "352": emit(.whois(networkID: networkID, text: formatWho(msg)))
        case "315": break                                    // end of WHO — marker only
        case "314", "369": emit(.whois(networkID: networkID, text: formatWhois(msg)))

        // ---- Invites / invite & except lists ----
        case "341":   // RPL_INVITING <me> <nick> <channel>
            if msg.params.count >= 3 {
                emitToChannel(msg.params[2], "*** Invited \(msg.params[1]) to \(msg.params[2])")
            } else { emitNumeric(msg) }
        case "346", "347", "348", "349":
            emitNumeric(msg)

        // ---- Undernet SILENCE list ----
        case "271", "272":
            emit(.serverLine(networkID: networkID, text: msg.params.dropFirst().joined(separator: " ")))

        // ---- Server-sent errors & notices that are not numerics ----
        case "ERROR":
            emit(.serverLine(networkID: networkID, text: "*** Server error: \(msg.params.last ?? "")"))
            emit(.stateChanged(networkID: networkID, .disconnected))
        case "WALLOPS":
            emit(.serverLine(networkID: networkID,
                             text: "*** WALLOPS from \(msg.sourceNick ?? "server"): \(msg.params.last ?? "")"))
        case "KILL":
            let who = msg.params.first ?? ""
            emit(.serverLine(networkID: networkID,
                             text: "*** \(who) was killed by \(msg.sourceNick ?? "server"): \(msg.params.last ?? "")"))
        case "SILENCE":
            emit(.serverLine(networkID: networkID, text: "*** SILENCE \(msg.params.joined(separator: " "))"))
        case "ACCOUNT":
            if let who = msg.sourceNick {
                let acct = msg.params.last ?? "*"
                emit(.serverLine(networkID: networkID,
                                 text: acct == "*" ? "*** \(who) logged out"
                                                   : "*** \(who) is now logged in as \(acct)"))
            }
        case "CHGHOST":
            if let who = msg.sourceNick, msg.params.count >= 2 {
                emit(.serverLine(networkID: networkID,
                                 text: "*** \(who) is now \(msg.params[0])@\(msg.params[1])"))
            }

        default:
            // Every remaining numeric is rendered readably and routed to the
            // channel it concerns when it names one; unknown non-numeric verbs
            // are still surfaced rather than swallowed.
            if Int(msg.command) != nil {
                emitNumeric(msg)
            } else if let src = msg.prefix, !src.isEmpty {
                let body = msg.params.joined(separator: " ")
                if !body.isEmpty {
                    emit(.serverLine(networkID: networkID, text: "\(msg.command) \(body)"))
                }
            }
        }
    }

    // MARK: Generic numeric rendering (RFC 1459 / 2812 + ircu)

    /// Channel prefix characters this server uses (RPL_ISUPPORT CHANTYPES).
    private var chanTypes = "#&"
    /// Everything RPL_ISUPPORT told us, for reference and future use.
    private var isupport: [String: String] = [:]

    private func isChannel(_ s: String) -> Bool {
        guard let f = s.first else { return false }
        return chanTypes.contains(f)
    }

    private func handleISupport(_ msg: IRCMessage) {
        // <me> <TOKEN[=value]>… :are supported by this server
        for token in msg.params.dropFirst().dropLast() {
            let bits = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = bits.first, !key.isEmpty else { continue }
            let value = bits.count > 1 ? bits[1] : ""
            isupport[key.uppercased()] = value
            if key.uppercased() == "CHANTYPES", !value.isEmpty { chanTypes = value }
        }
        let summary = msg.params.dropFirst().dropLast().joined(separator: " ")
        if !summary.isEmpty { emit(.serverLine(networkID: networkID, text: summary)) }
    }

    /// Send a line into a channel's window — but only if that window already
    /// exists (the app decides); otherwise it lands in the server console. A
    /// numeric about a channel you are NOT in must never create a sidebar row,
    /// or the next reconnect would auto-rejoin it.
    private func emitToChannel(_ channel: String, _ text: String) {
        guard isChannel(channel) else {
            emit(.serverLine(networkID: networkID, text: text)); return
        }
        emit(.contextLine(conversationID: "\(networkID)/\(channel)", text: text))
    }

    /// Render any numeric as a readable line: "<subject> — <text>", named when
    /// we know the numeric, prefixed "***" for errors (4xx/5xx), and delivered
    /// to the channel window when the numeric names a channel.
    private func emitNumeric(_ msg: IRCMessage) {
        let code = msg.command
        var fields = msg.params
        if fields.count > 1 { fields.removeFirst() }        // drop the <me> target
        let text = fields.popLast() ?? ""
        // Scan for a channel only among the SUBJECT params — the human text is
        // free-form and may legitimately start with '#'.
        let channel = fields.first(where: { isChannel($0) })
        let subject = fields.joined(separator: " ")

        var line: String
        if subject.isEmpty { line = text }
        else if text.isEmpty { line = subject }
        else { line = "\(subject) — \(text)" }
        if line.isEmpty { line = Self.numericNames[code] ?? code }

        let isError = code.hasPrefix("4") || code.hasPrefix("5")
        if isError {
            let name = Self.numericNames[code]
            line = "*** " + line + (name == nil ? " (\(code))" : "")
        }
        if let channel { emitToChannel(channel, line) }
        else { emit(.serverLine(networkID: networkID, text: line)) }
    }

    /// RPL_WHOREPLY 352: <me> <chan> <user> <host> <server> <nick> <flags> :<hops> <real>
    private func formatWho(_ msg: IRCMessage) -> String {
        let p = msg.params
        guard p.count >= 7 else { return msg.params.dropFirst().joined(separator: " ") }
        let chan = p[1], user = p[2], host = p[3], nick = p[5], flags = p[6]
        let real = (msg.params.last ?? "").split(separator: " ").dropFirst().joined(separator: " ")
        var marks: [String] = []
        if flags.contains("G") { marks.append("away") }
        if flags.contains("*") { marks.append("ircop") }
        if flags.contains("@") { marks.append("op") }
        if flags.contains("+") { marks.append("voice") }
        let suffix = marks.isEmpty ? "" : " [\(marks.joined(separator: ", "))]"
        return "\(nick) \(user)@\(host) on \(chan)\(suffix) — \(real)"
    }

    /// Names for the numerics we render generically — RFC 1459/2812 plus the
    /// ircu (Undernet) additions. Used to label errors; unknown codes still
    /// render their text.
    private static let numericNames: [String: String] = [
        // command responses
        "200": "TRACELINK", "201": "TRACECONNECTING", "202": "TRACEHANDSHAKE",
        "203": "TRACEUNKNOWN", "204": "TRACEOPERATOR", "205": "TRACEUSER",
        "206": "TRACESERVER", "208": "TRACENEWTYPE", "209": "TRACECLASS",
        "211": "STATSLINKINFO", "212": "STATSCOMMANDS", "213": "STATSCLINE",
        "214": "STATSNLINE", "215": "STATSILINE", "216": "STATSKLINE",
        "217": "STATSQLINE", "218": "STATSYLINE", "219": "ENDOFSTATS",
        "221": "UMODEIS", "222": "STATSJLINE", "231": "SERVICEINFO",
        "234": "SERVLIST", "235": "SERVLISTEND", "241": "STATSLLINE",
        "242": "STATSUPTIME", "243": "STATSOLINE", "244": "STATSHLINE",
        "246": "STATSPING", "247": "STATSGLINE", "248": "STATSULINE",
        "261": "TRACELOG", "262": "TRACEEND", "263": "TRYAGAIN",
        "280": "GLIST", "281": "ENDOFGLIST", "304": "TEXT",
        "307": "WHOISREGNICK", "310": "WHOISHELPOP", "320": "WHOISSPECIAL",
        "334": "LISTUSAGE", "335": "WHOISBOT", "379": "WHOISMODES",
        "381": "YOUREOPER", "382": "REHASHING", "391": "TIME",
        "392": "USERSSTART", "393": "USERS", "394": "ENDOFUSERS", "395": "NOUSERS",
        // errors
        "401": "No such nick/channel", "402": "No such server",
        "403": "No such channel", "404": "Cannot send to channel",
        "405": "Too many channels", "406": "No such nick (was)",
        "407": "Too many targets", "408": "No such service",
        "409": "No origin specified", "411": "No recipient given",
        "412": "No text to send", "413": "No toplevel domain",
        "414": "Wildcard in toplevel domain", "421": "Unknown command",
        "422": "No MOTD", "423": "No admin info", "424": "File error",
        "431": "No nickname given", "432": "Erroneous nickname",
        "433": "Nickname is already in use", "436": "Nick collision",
        "437": "Nick/channel temporarily unavailable",
        "438": "Nick change too fast", "439": "Target change too fast",
        "441": "They aren't on that channel", "442": "You're not on that channel",
        "443": "Is already on channel", "444": "User not logged in",
        "445": "SUMMON disabled", "446": "USERS disabled",
        "451": "You have not registered", "461": "Not enough parameters",
        "462": "You may not reregister", "463": "Your host isn't among the privileged",
        "464": "Password incorrect", "465": "You are banned from this server",
        "466": "You will be banned", "467": "Channel key already set",
        "471": "Channel is full", "472": "Unknown mode char",
        "473": "Invite only channel", "474": "You are banned from the channel",
        "475": "Bad channel key", "476": "Bad channel mask",
        "477": "Needs a registered nick", "478": "Channel ban list is full",
        "481": "Permission denied — you're not an IRC operator",
        "482": "You're not channel operator", "483": "You can't kill a server",
        "484": "Your connection is restricted", "485": "Not the original channel operator",
        "491": "No O-lines for your host", "492": "No CTCP allowed",
        "501": "Unknown MODE flag", "502": "Can't change mode for other users",
        "511": "Silence list is full", "512": "Too many watch entries",
        "513": "Bad PING response", "524": "No such help topic",
    ]

    /// Next nick to try on a collision: the configured alternate first, then the
    /// base nick with growing underscores, then a numeric suffix.
    private func nextNick() -> String {
        // Ladder from the nick we are actually trying to register with, not the
        // one this object was created with — a persisted rename would otherwise
        // fall back to the old config's nick.
        let base = configNick.isEmpty ? baseNick : configNick
        nickAttempt += 1
        if nickAttempt == 1, !altNick.isEmpty, altNick != base { return altNick }
        if nickAttempt <= 3 { return base + String(repeating: "_", count: nickAttempt) }
        return base + "\(nickAttempt)"
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
        guard isChannel(target) else { return }
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
                applyMode(ch, adding: adding, arg: arg, convID: convID, by: msg.sourceNick)
            }
        }
    }

    private func applyMode(_ ch: Character, adding: Bool, arg: String?, convID: String, by: String? = nil) {
        switch ch {
        case "o":
            if let nick = arg { emit(.modeChanged(conversationID: convID, nick: nick, mode: adding ? .op : .regular)) }
        case "v":
            if let nick = arg { emit(.modeChanged(conversationID: convID, nick: nick, mode: adding ? .voice : .regular)) }
        case "b":
            if let mask = arg { emit(.ban(conversationID: convID, mask: mask, added: adding, by: by ?? "")) }
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

    // MARK: Sending — paced queue (ircu "Excess Flood" protection)

    // mIRC-style penalty clock: the timer may run up to ~4s ahead of now (a
    // burst of 5 quick lines); past that every line waits so we never exceed
    // ~1 line/sec sustained and the server never kills us for flooding.
    private var sendQueue: [String] = []
    private var sendPump: Task<Void, Never>?
    private var sendTimer: Date = .distantPast
    /// While a QUIT is being written, nothing else may join the queue.
    /// disconnect() used to cancel the pump and drop the queue, which threw
    /// away the QUIT along with everything else.
    private var closing = false

    private func rawSend(_ s: String) {
        guard !closing else { return }
        sendQueue.append(s)
        if sendPump == nil {
            sendPump = Task { [weak self] in await self?.drainSendQueue() }
        }
    }

    private func drainSendQueue() async {
        while !sendQueue.isEmpty {
            if Task.isCancelled { break }
            let now = Date()
            if sendTimer < now { sendTimer = now }
            let ahead = sendTimer.timeIntervalSince(now)
            if ahead > 4 {
                try? await Task.sleep(for: .seconds(ahead - 4))
                if Task.isCancelled { break }
            }
            guard !sendQueue.isEmpty else { break }
            let line = sendQueue.removeFirst()
            connection?.send(content: line.data(using: .utf8), completion: .contentProcessed { _ in })
            sendTimer.addTimeInterval(1)
        }
        sendPump = nil
    }

    func disconnect(networkID: String, quitMessage: String) async {
        guard !closing else { return }
        closing = true
        let conn = connection
        let pump = sendPump
        sendPump = nil
        pump?.cancel()
        sendQueue.removeAll()
        // Let the pump notice the cancel before we write. Otherwise its next
        // send can land on the socket after QUIT, or instead of it.
        await pump?.value
        if let conn {
            await writeLine(IRCParser.quitLine(message: quitMessage), on: conn)
            conn.cancel()
            if connection === conn { connection = nil }
        }
        closing = false
        emit(.stateChanged(networkID: networkID, .disconnected))
    }

    /// QUIT has to reach the kernel before cancel(). The completion is that
    /// signal. The timeout covers a socket that will never call back.
    private func writeLine(_ line: String, on conn: NWConnection) async {
        let data = Data(line.utf8)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let gate = OnceResume()
            conn.send(content: data, completion: .contentProcessed { _ in
                gate.perform { cont.resume() }
            })
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
                gate.perform { cont.resume() }
            }
        }
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
    func join(channel: String, key: String?, networkID: String) async {
        if let key, !key.isEmpty {
            rawSend(IRCParser.serialize(command: "JOIN", params: [channel, key]))
        } else {
            rawSend(IRCParser.serialize(command: "JOIN", params: [channel]))
        }
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
        // Optimistic, but remembered: if the server refuses (432/433/436/437/438)
        // we roll back, or every later self-check compares against a nick we
        // never actually held.
        // Only the first pending change records the rollback target — a second
        // /nick in flight must not make a never-held candidate the fallback.
        if previousNick == nil { previousNick = self.nick }
        self.nick = nick
        guard connection != nil else {
            // Chosen before we connect (private session) — this IS the nick we
            // will register with; there is no socket to tell.
            nickOverride = nick
            previousNick = nil
            return
        }
        rawSend(IRCParser.serialize(command: "NICK", params: [nick]))
    }

    /// Keep the transport's idea of the configured nick current (settings edit
    /// or a persisted rename), so the next connect registers correctly.
    func updateNick(_ n: String) {
        guard !n.isEmpty else { return }
        configNick = n
    }
    func whois(nick: String, conversationID: String) async {
        // "WHOIS <nick> <nick>" queries the server the user is ON — required
        // for idle time (317) and away status (301) to come back.
        rawSend(IRCParser.serialize(command: "WHOIS", params: [nick, nick]))
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

/// First caller wins. QUIT's send completion and the timeout both try to
/// resume the same continuation.
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func perform(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

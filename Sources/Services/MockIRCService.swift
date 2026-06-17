import Foundation

/// In-memory IRC service that drives the UI with realistic data and a periodic
/// "live" chatter timer — no server required. Conforms to the same `IRCClient`
/// protocol as `LiveIRCClient`, so the app is fully interactive offline and
/// swapping to the real transport is a one-line change in `AppModel`.
final class MockIRCService: IRCClient, @unchecked Sendable {

    nonisolated let events: AsyncStream<IRCEvent>
    private let continuation: AsyncStream<IRCEvent>.Continuation
    private var chatterTimer: Timer?

    init() {
        var cont: AsyncStream<IRCEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
        startChatter()
        demoCTCP()
    }

    /// Show the CTCP behaviour offline: a couple of incoming requests and our
    /// silly replies land in the server console.
    private func demoCTCP() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.emit(.serverLine(networkID: "undernet", text: "[CTCP] VERSION from ozric → \(CTCP.versionReply)"))
            try? await Task.sleep(for: .seconds(2))
            let pong = CTCP.reply(to: "PING", argument: "1700000000", seed: 5) ?? ""
            self?.emit(.serverLine(networkID: "undernet", text: "[CTCP] PING from nyx → \(pong)"))
        }
    }

    deinit { chatterTimer?.invalidate() }

    private func emit(_ e: IRCEvent) { continuation.yield(e) }
    private func mid() -> String { "m\(Int.random(in: 100000...999999))" }

    // MARK: Connection lifecycle (simulated)

    func connect(networkID: String) async {
        emit(.stateChanged(networkID: networkID, .connecting))
        let lines = [
            "*** Connecting to \(serverFor(networkID))…",
            "*** TLS handshake complete (TLSv1.3)",
            "*** Checking ident…",
            "*** Registering connection…"
        ]
        for (i, l) in lines.enumerated() {
            try? await Task.sleep(for: .milliseconds(500 + i * 600))
            emit(.serverLine(networkID: networkID, text: l))
        }
        emit(.stateChanged(networkID: networkID, .registering))
        try? await Task.sleep(for: .milliseconds(700))
        emit(.stateChanged(networkID: networkID, .connected))
        emit(.serverLine(networkID: networkID, text: "*** Welcome to \(networkID). Have fun."))
    }

    func disconnect(networkID: String) async {
        emit(.stateChanged(networkID: networkID, .disconnected))
    }

    private func serverFor(_ id: String) -> String {
        switch id {
        case "undernet": return "Ann-Arbor.MI.US.Undernet.org"
        case "efnet":    return "irc.efnet.org"
        default:         return "irc.libera.chat"
        }
    }

    // MARK: Outgoing actions — echo back as the appropriate event

    func sendRaw(_ line: String, networkID: String) async {
        // Surface the executed command in the server console so on-connect
        // automation is visible in the offline demo.
        emit(.serverLine(networkID: networkID, text: ">> \(line)"))
    }

    func send(text: String, to conversationID: String) async {
        emit(.message(conversationID: conversationID,
                      Message(id: mid(), kind: .message, nick: AppModel.selfNickPlaceholder, text: text)))
    }
    func sendAction(_ action: String, to conversationID: String) async {
        emit(.message(conversationID: conversationID,
                      Message(id: mid(), kind: .action, nick: AppModel.selfNickPlaceholder, text: action)))
    }
    func join(channel: String, networkID: String) async {
        let id = "\(networkID)/\(channel)"
        emit(.message(conversationID: id, Message(id: mid(), kind: .server, text: "*** Now talking in \(channel)")))
    }
    func part(conversationID: String) async { /* handled in AppModel by removing the conv */ }
    func setTopic(_ topic: String, conversationID: String) async {
        emit(.topic(conversationID: conversationID, topic))
    }
    func changeNick(_ nick: String, networkID: String) async {
        emit(.nickChanged(networkID: networkID, from: AppModel.selfNickPlaceholder, to: nick))
    }
    func whois(nick: String, conversationID: String) async {
        let host = "~\(nick.lowercased())@\(nick.lowercased()).users.undernet.org"
        for line in [
            "\(nick) is \(host) * \(nick)",
            "\(nick) on #coder-com #wasteland",
            "\(nick) using \(serverFor("undernet")) [Undernet]",
            "\(nick) has been idle 4mins 12secs, signed on today at 09:14",
            "\(nick) is logged in as \(nick)",
            "End of /WHOIS list."
        ] {
            emit(.message(conversationID: conversationID, Message(id: mid(), kind: .whois, text: line)))
        }
    }
    func setMode(_ mode: MemberMode, nick: String, conversationID: String) async {
        emit(.modeChanged(conversationID: conversationID, nick: nick, mode: mode))
    }
    func kick(nick: String, conversationID: String) async {
        emit(.memberLeft(conversationID: conversationID, nick: nick, reason: "kicked", kind: .part))
    }

    // MARK: Live chatter — periodic incoming messages

    private struct Chatter { let conv: String; let nick: String; let text: String; let mention: Bool }
    private let pool: [Chatter] = [
        .init(conv: "undernet/#coder-com", nick: "lain", text: "rebuilt against the new libuv, no leaks after 2h soak", mention: false),
        .init(conv: "undernet/#coder-com", nick: "ozric", text: "mcimpeanu nice work on the parser btw", mention: true),
        .init(conv: "undernet/#coder-com", nick: "nyx", text: "X is happy again, eu split fully healed", mention: false),
        .init(conv: "undernet/#wasteland", nick: "rover", text: "archived another 400MB of logs from 2003", mention: false),
        .init(conv: "undernet/#help", nick: "zoe", text: "how do I set +R so only registered nicks can talk?", mention: false),
    ]

    private func startChatter() {
        chatterTimer = Timer.scheduledTimer(withTimeInterval: 5.2, repeats: true) { [weak self] _ in
            guard let self, let c = self.pool.randomElement() else { return }
            self.emit(.message(conversationID: c.conv,
                               Message(id: self.mid(), kind: .message, nick: c.nick, text: c.text)))
        }
    }

    // MARK: Seed data — the initial world the app boots into

    static func seedNetworks() -> [Network] {
        [
            Network(id: "undernet", name: "Undernet", server: "Ann-Arbor.MI.US.Undernet.org",
                    nick: "mcimpeanu", state: .connected, isExpanded: true,
                    conversationIDs: ["undernet/#coder-com", "undernet/#help", "undernet/#wasteland",
                                      "undernet/#zelda", "undernet/catnip", "undernet/X"]),
            Network(id: "efnet", name: "EFnet", server: "irc.efnet.org",
                    nick: "mci", state: .registering, isExpanded: true,
                    conversationIDs: ["efnet/#linux", "efnet/#c"]),
            Network(id: "libera", name: "Libera.Chat", server: "irc.libera.chat",
                    nick: "m_c", state: .disconnected, isExpanded: false,
                    conversationIDs: ["libera/#irc"]),
        ]
    }

    static func seedConversations() -> [String: Conversation] {
        var c: [String: Conversation] = [:]
        func member(_ n: String, _ m: MemberMode = .regular, away: Bool = false) -> Member {
            Member(nick: n, mode: m, isAway: away)
        }
        func msg(_ id: String, _ kind: MessageKind, nick: String = "", text: String = "",
                 preview: LinkPreview? = nil) -> Message {
            Message(id: id, kind: kind, nick: nick, text: text, preview: preview)
        }

        c["undernet/$server"] = Conversation(id: "undernet/$server", kind: .server, name: "Undernet", messages: [
            msg("sv1", .server, text: "*** Looking up your hostname..."),
            msg("sv3", .server, text: "*** Connected to Ann-Arbor.MI.US.Undernet.org (port 6697, TLSv1.3)"),
            msg("sv5", .server, text: "- Welcome to the Undernet IRC Network. Please read the AUP: https://www.undernet.org/aup"),
            msg("sv8", .notice, nick: "X", text: "AUTHENTICATION SUCCESSFUL. You are now logged in as mcimpeanu."),
        ])

        c["undernet/#coder-com"] = Conversation(
            id: "undernet/#coder-com", kind: .channel, name: "#coder-com",
            topic: "Undernet coder-com · ircd dev & ops · https://github.com/coder-com/ircd · release freeze Fri 17:00 UTC",
            members: [
                member("X", .op), member("Gandalf", .op), member("sparky", .op), member("nuke", .op),
                member("ada", .voice), member("mizilla", .voice),
                member("biff"), member("dex"), member("ev"), member("fenn"), member("gus", away: true),
                member("hex"), member("klein", away: true), member("lain"), member("mara", away: true),
                member("mcimpeanu"), member("nyx"), member("ozric"), member("packet"), member("q0re"),
                member("tory"), member("void"),
            ],
            messages: [
                msg("cc1", .join, nick: "void", text: "~void@host-12-44.pool.undernet.org"),
                msg("cc2", .join, nick: "ada", text: "~ada@gw.geneva.ch"),
                msg("cc4", .quit, nick: "klein", text: "Ping timeout: 248 seconds"),
                msg("cc6", .message, nick: "sparky", text: "@X is being slow again — anyone else seeing auth lag this morning?"),
                msg("cc7", .message, nick: "void", text: "yeah X took ~30s to op me earlier"),
                msg("cc8", .message, nick: "ada", text: "it's the EU split, Ann-Arbor is fine though"),
                msg("cc10", .action, nick: "biff", text: "kicks the routing table until it behaves"),
                msg("cc11", .message, nick: "q0re", text: "pushed the parser fix → https://github.com/coder-com/ircd/pull/482",
                    preview: LinkPreview(kind: .link, title: "parser: handle IRCv3 message tags before the prefix · PR #482", meta: "github.com · coder-com/ircd · +212 −38")),
                msg("cc12", .message, nick: "q0re", text: "flamegraph after the fix, p99 parse time down ~40%:",
                    preview: LinkPreview(kind: .image, label: "flamegraph-after.png", dims: "1840 × 720")),
                msg("cc13", .notice, nick: "X", text: "You have been opped on #coder-com. Channel modes are now synced."),
                msg("cc14", .message, nick: "packet", text: "mcimpeanu: did you get a chance to review #482? would love to ship before the freeze"),
                msg("cc15", .message, nick: "lain", text: "I can take a pass too if it helps split the load"),
            ],
            declaredMemberCount: 47)

        c["undernet/#help"] = Conversation(
            id: "undernet/#help", kind: .channel, name: "#help",
            topic: "Welcome to #help · Nick & channel registration via X · read the FAQ first · no flooding",
            members: [member("Servo", .op), member("helpdesk", .voice), member("frank"), member("newbie22"),
                      member("zoe"), member("rk"), member("tilde"), member("opus"), member("vee"), member("mcimpeanu")],
            messages: [
                msg("hp1", .message, nick: "Servo", text: "Welcome to #help! To register your nick: /msg X@channels.undernet.org help register"),
                msg("hp2", .message, nick: "newbie22", text: "how do I get my channel back? X keeps saying I'm not authed"),
                msg("hp3", .message, nick: "frank", text: "newbie22: /msg x@channels.undernet.org login <user> <pass>"),
                msg("hp4", .message, nick: "newbie22", text: "ohh that worked, thank you!!"),
            ],
            unread: 3, firstUnreadID: "hp2", declaredMemberCount: 89)

        c["undernet/#wasteland"] = Conversation(
            id: "undernet/#wasteland", kind: .channel, name: "#wasteland",
            topic: "the wasteland · off-topic & archives · no warez · SCAVENGE responsibly",
            members: [member("Wraith", .op), member("rover"), member("salv"), member("grit"),
                      member("mole"), member("ash"), member("dune"), member("pax"), member("mcimpeanu")],
            messages: [
                msg("wl1", .message, nick: "Wraith", text: "reminder: no warez talk in here, this is a scavenge & archive channel"),
                msg("wl2", .message, nick: "rover", text: "found a working mirror of the old undernet ops docs"),
                msg("wl4", .message, nick: "salv", text: "mcimpeanu you around? need a hand with /msg X login, it keeps rejecting me"),
                msg("wl5", .message, nick: "salv", text: "never mind — had caps lock on. classic 🙂"),
            ],
            unread: 2, mentions: 1, firstUnreadID: "wl4", declaredMemberCount: 31)

        c["undernet/#zelda"] = Conversation(
            id: "undernet/#zelda", kind: .channel, name: "#zelda",
            topic: "it's dangerous to go alone · OoT any% run tonight 21:00 · spoilers tagged",
            members: [member("navi", .op), member("link2"), member("zora"), member("saria"), member("darknut"), member("mcimpeanu")],
            messages: [
                msg("zl1", .message, nick: "navi", text: "hey! listen!"),
                msg("zl2", .message, nick: "link2", text: "speedrun tonight at 21:00, any% no wrong-warp. who is in"),
            ],
            declaredMemberCount: 12)

        c["undernet/catnip"] = Conversation(
            id: "undernet/catnip", kind: .directMessage, name: "catnip",
            messages: [
                msg("dm1", .message, nick: "catnip", text: "did the SASL patch land yet?"),
                msg("dm2", .message, nick: "mcimpeanu", text: "almost — q0re's reviewing #482 right now"),
                msg("dm3", .message, nick: "catnip", text: "nice. ping me the second it's merged and I'll cut a release"),
            ],
            unread: 1, mentions: 1, firstUnreadID: "dm3")

        c["undernet/X"] = Conversation(
            id: "undernet/X", kind: .directMessage, name: "X",
            messages: [
                msg("x1", .message, nick: "mcimpeanu", text: "login mcimpeanu ********"),
                msg("x2", .notice, nick: "X", text: "AUTHENTICATION SUCCESSFUL. Last login from 84.12.x.x on Jun 16."),
            ])

        c["efnet/$server"] = Conversation(id: "efnet/$server", kind: .server, name: "EFnet")
        c["efnet/#linux"] = Conversation(
            id: "efnet/#linux", kind: .channel, name: "#linux",
            topic: "#linux · distro-agnostic help · paste >3 lines to a pastebin",
            members: [member("tux", .op), member("kern", .op), member("initd", .voice), member("grub"), member("sysd"), member("mci")],
            messages: [
                msg("lx1", .message, nick: "kern", text: "anyone running the 6.9 rc on btrfs? seeing weird stalls under fio"),
                msg("lx2", .message, nick: "initd", text: "works here, but I pinned the scheduler to mq-deadline"),
            ],
            declaredMemberCount: 412)
        c["efnet/#c"] = Conversation(
            id: "efnet/#c", kind: .channel, name: "#c",
            topic: "#c · the C programming language · read the FAQ, then ask",
            members: [member("ritchie", .op), member("ptr"), member("malloc"), member("mci")],
            messages: [msg("c1", .message, nick: "ptr", text: "no, you still have to free it")],
            declaredMemberCount: 198)

        c["libera/$server"] = Conversation(id: "libera/$server", kind: .server, name: "Libera.Chat")
        c["libera/#irc"] = Conversation(id: "libera/#irc", kind: .channel, name: "#irc")

        return c
    }
}

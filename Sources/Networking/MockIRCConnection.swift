import Foundation

/// In-memory connection that scripts a believable IRC session so the whole UI
/// is interactive without a server. Echoes sent messages back into the buffer.
actor MockIRCConnection: IRCConnection {
    nonisolated let events: AsyncStream<IRCEvent>
    private nonisolated let continuation: AsyncStream<IRCEvent>.Continuation
    private let config: ServerConfig

    init(config: ServerConfig) {
        self.config = config
        let (stream, cont) = AsyncStream<IRCEvent>.makeStream()
        self.events = stream
        self.continuation = cont
    }

    func start() async {
        emit(.stateChanged(.connecting))
        await nap(0.3)
        emit(.stateChanged(.registering))
        await nap(0.3)
        emit(.stateChanged(.connected))

        for channel in seededChannels(for: config) {
            emit(.channelJoined(name: channel.name, topic: channel.topic))
            emit(.topic(channel: channel.name, channel.topic))
            emit(.members(channel: channel.name, channel.members))
            for line in channel.backlog {
                emit(.line(channel: channel.name, line))
            }
        }

        // A DM already waiting with an unread mention.
        emit(.privateMessage(peer: "marlowe", ChatLine(
            kind: .message, sender: "marlowe",
            text: "\(config.nick): did the TLS handshake patch land?", isMention: true)))

        // Keep a little ambient chatter going.
        await ambientChatter()
    }

    func send(line: String) async {
        guard let msg = IRCProtocolParser.parse(line) ?? fallback(line) else { return }
        switch msg.command {
        case "PRIVMSG":
            let target = msg.params.first ?? ""
            let body = msg.params.last ?? ""
            if body.hasPrefix("\u{01}ACTION") {
                let action = body.dropFirst(7).dropLast().trimmingCharacters(in: .whitespaces)
                emit(.line(channel: target, ChatLine(kind: .action, sender: config.nick, text: action)))
            } else {
                emit(.line(channel: target, ChatLine(kind: .message, sender: config.nick, text: body)))
            }
        case "JOIN":
            let name = msg.params.first ?? "#channel"
            emit(.channelJoined(name: name, topic: ""))
            emit(.members(channel: name, [Member(nick: config.nick), Member(nick: "guide", prefix: .op)]))
        case "PART":
            emit(.channelParted(name: msg.params.first ?? ""))
        default:
            break
        }
    }

    func stop() async {
        emit(.stateChanged(.disconnected))
        continuation.finish()
    }

    // MARK: - Helpers

    private nonisolated func emit(_ event: IRCEvent) {
        continuation.yield(event)
    }

    private func nap(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Treat a bare "/raw"-stripped string as a PRIVMSG to nowhere.
    private func fallback(_ line: String) -> IRCProtocolMessage? {
        IRCProtocolMessage(command: "PRIVMSG", params: ["#status", line])
    }

    private func ambientChatter() async {
        let beats: [(String, String, String)] = [
            ("#swift", "audrey", "anyone using Observation in anger yet?"),
            ("#swift", "ben", "yeah, swapped all our ObservableObjects last month, zero regrets"),
            ("#macdev", "cole", "NSVisualEffectView still the move for proper vibrancy"),
            ("#swift", "audrey", "the macro debugging story is… fine"),
        ]
        for (channel, who, text) in beats {
            await nap(2.5)
            emit(.line(channel: channel, ChatLine(kind: .message, sender: who, text: text)))
        }
    }

    private struct SeedChannel {
        var name: String
        var topic: String
        var members: [Member]
        var backlog: [ChatLine]
    }

    private func seededChannels(for config: ServerConfig) -> [SeedChannel] {
        let nick = config.nick
        return [
            SeedChannel(
                name: "#swift",
                topic: "Swift language & SwiftUI — be kind, paste code in a gist",
                members: [
                    Member(nick: "audrey", prefix: .op),
                    Member(nick: "ben", prefix: .voice),
                    Member(nick: nick),
                    Member(nick: "cole"),
                    Member(nick: "dana", isAway: true),
                ],
                backlog: [
                    ChatLine(kind: .server, sender: "*", text: "Now talking in #swift"),
                    ChatLine(kind: .message, sender: "audrey", text: "morning all"),
                    ChatLine(kind: .message, sender: "ben", text: "check out https://swift.org/blog — new concurrency notes"),
                    ChatLine(kind: .action, sender: "cole", text: "is reading the migration guide so you don't have to"),
                    ChatLine(kind: .message, sender: "audrey", text: "\(nick): welcome 👋", isMention: true),
                ]),
            SeedChannel(
                name: "#macdev",
                topic: "Cocoa, AppKit, SwiftUI on the Mac",
                members: [
                    Member(nick: "cole", prefix: .op),
                    Member(nick: nick),
                    Member(nick: "erin", prefix: .voice),
                ],
                backlog: [
                    ChatLine(kind: .server, sender: "*", text: "Now talking in #macdev"),
                    ChatLine(kind: .message, sender: "erin", text: "NavigationSplitView column widths finally behave in 14.4"),
                    ChatLine(kind: .join, sender: "frank", text: "frank joined"),
                ]),
        ]
    }
}

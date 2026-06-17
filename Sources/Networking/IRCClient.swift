import Foundation

// MARK: - Events emitted by any IRC client up to the view models

/// Everything a client (mock or live) can tell the app. The view model is the
/// single consumer; it mutates `AppModel` state in response. Keeping this as a
/// value-type event stream means the mock and the live `NWConnection` client are
/// interchangeable behind `IRCClient`.
enum IRCEvent {
    case stateChanged(networkID: String, ConnectionState)
    case serverLine(networkID: String, text: String)
    case message(conversationID: String, Message)
    case topic(conversationID: String, String)
    case members(conversationID: String, [Member])
    case memberJoined(conversationID: String, Member)
    case memberLeft(conversationID: String, nick: String, reason: String, kind: MessageKind)
    case modeChanged(conversationID: String, nick: String, mode: MemberMode)
    case nickChanged(networkID: String, from: String, to: String)
}

// MARK: - The single protocol both clients implement

/// The seam that makes "swap mock for live a one-line change". Both
/// `MockIRCService` and `LiveIRCClient` conform; the app talks only to this.
protocol IRCClient: AnyObject {
    /// Async stream of events for the UI to consume.
    var events: AsyncStream<IRCEvent> { get }

    func connect(networkID: String) async
    func disconnect(networkID: String) async

    /// Send a raw IRC protocol line on a network (used by on-connect perform
    /// commands). Implementations append CRLF as needed.
    func sendRaw(_ line: String, networkID: String) async

    func send(text: String, to conversationID: String) async
    func sendAction(_ action: String, to conversationID: String) async
    func join(channel: String, networkID: String) async
    func part(conversationID: String) async
    func setTopic(_ topic: String, conversationID: String) async
    func changeNick(_ nick: String, networkID: String) async
    func whois(nick: String, conversationID: String) async
    func setMode(_ mode: MemberMode, nick: String, conversationID: String) async
    func kick(nick: String, conversationID: String) async
}

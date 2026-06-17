import Foundation

/// Transport-agnostic IRC connection. Both the in-memory mock and the live
/// `NWConnection`-backed client conform to this, so the rest of the app never
/// knows which one it is talking to.
protocol IRCConnection: Sendable {
    /// Stream of events the connection emits. Begin iterating before `start()`.
    var events: AsyncStream<IRCEvent> { get }
    func start() async
    func send(line: String) async
    func stop() async
}

/// Single swap-point between mock and live. Flip the returned type to go live.
enum IRCConnectionFactory {
    static func make(config: ServerConfig) -> any IRCConnection {
        MockIRCConnection(config: config)
        // LiveIRCConnection(config: config)   // ← one-line change to go live
    }
}

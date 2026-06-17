import Foundation

/// One command to run automatically when a connection registers, with an
/// optional delay applied *before* it is sent. The on-connect list runs in
/// order, and the whole list completes before any auto-join channels are joined.
struct PerformCommand: Identifiable, Hashable, Codable {
    var id = UUID()
    /// What you'd type in the composer, e.g. `/msg NickServ identify hunter2`
    /// or a raw IRC line like `MODE %nick% +x`. `%nick%` is substituted.
    var line: String = ""
    /// Seconds to wait before sending this command.
    var delay: Double = 0
}

/// Persisted, user-editable configuration for a single IRC server/network.
/// This is the durable record; `Network` is the live runtime state. They are
/// matched by `id`.
struct ServerConfig: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString

    // Server
    var name: String = "New Network"
    var host: String = "irc.example.net"
    var port: Int = 6697
    var useTLS: Bool = true

    // Identity
    var nick: String = ""
    var altNick: String = ""
    var username: String = ""
    var realName: String = "Relay"
    var serverPassword: String = ""

    // Authentication (SASL PLAIN)
    var saslEnabled: Bool = false
    var saslAccount: String = ""
    var saslPassword: String = ""

    // User modes to set on this network right after connecting (e.g. "x", "w").
    var userModes: Set<String> = []

    // Behaviour
    var connectOnLaunch: Bool = false
    var autoReconnect: Bool = true

    // On-connect automation — runs in order, then (after joinDelay) the joins.
    var onConnectCommands: [PerformCommand] = []
    var joinDelay: Double = 0
    var autoJoinChannels: [String] = []

    var effectiveUsername: String { username.isEmpty ? nick : username }
}

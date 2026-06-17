import Foundation

// MARK: - Connection state machine

enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case registering
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .registering:  return "Registering…"
        case .connected:    return "Connected"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    var isOnline: Bool { self == .connected }
}

// MARK: - Server configuration

struct ServerConfig: Sendable, Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var host: String
    var port: UInt16 = 6697
    var useTLS: Bool = true
    var nick: String
    var realName: String = "IRC for Mac"
    var autoJoin: [String] = []
}

// MARK: - Channel membership

struct Member: Sendable, Identifiable, Hashable {
    enum Prefix: Sendable, Comparable {
        case op, halfOp, voice, none
    }
    var id: String { nick }
    var nick: String
    var prefix: Prefix = .none
    var isAway: Bool = false

    var symbolName: String? {
        switch prefix {
        case .op:     return "shield.lefthalf.filled"
        case .halfOp: return "shield.lefthalf.filled"
        case .voice:  return "plus.circle.fill"
        case .none:   return nil
        }
    }

    var sigil: String {
        switch prefix {
        case .op:     return "@"
        case .halfOp: return "%"
        case .voice:  return "+"
        case .none:   return ""
        }
    }
}

// MARK: - A single rendered line in a channel buffer

struct ChatLine: Sendable, Identifiable {
    enum Kind: Sendable {
        case message
        case action      // /me
        case notice
        case join
        case part
        case quit
        case server
        case topic
    }

    var id = UUID()
    var timestamp: Date = .now
    var kind: Kind
    var sender: String
    var text: String
    var isMention: Bool = false

    var isCollapsible: Bool {
        switch kind {
        case .join, .part, .quit: return true
        default: return false
        }
    }
}

// MARK: - Events emitted by an IRC connection toward the view models

enum IRCEvent: Sendable {
    case stateChanged(ConnectionState)
    case channelJoined(name: String, topic: String)
    case channelParted(name: String)
    case line(channel: String, ChatLine)
    case privateMessage(peer: String, ChatLine)
    case members(channel: String, [Member])
    case topic(channel: String, String)
    case error(String)
}

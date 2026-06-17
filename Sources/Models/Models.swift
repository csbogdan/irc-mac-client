import Foundation
import SwiftUI

// MARK: - Connection state machine

enum ConnectionState: String, Codable, Equatable {
    case disconnected
    case connecting      // socket opening / TLS
    case registering     // sent NICK/USER, awaiting 001
    case connected

    var label: String {
        switch self {
        case .disconnected: return "offline"
        case .connecting:   return "connecting…"
        case .registering:  return "registering…"
        case .connected:    return ""
        }
    }

    var dotColor: Color {
        switch self {
        case .connected:   return Color(red: 0.20, green: 0.78, blue: 0.35)   // #34C759
        case .connecting, .registering: return Color(red: 1.0, green: 0.74, blue: 0.18) // #FEBC2E
        case .disconnected: return Color.secondary.opacity(0.5)
        }
    }

    var isLive: Bool { self == .connected }
    var isBusy: Bool { self == .connecting || self == .registering }
}

// MARK: - Member

enum MemberMode: String, Codable, CaseIterable {
    case op      // @
    case voice   // +
    case regular // (none)

    var glyph: String {
        switch self {
        case .op: return "@"
        case .voice: return "+"
        case .regular: return ""
        }
    }

    /// Sort rank: ops first, then voiced, then regular.
    var rank: Int {
        switch self {
        case .op: return 0
        case .voice: return 1
        case .regular: return 2
        }
    }
}

struct Member: Identifiable, Hashable {
    var id: String { nick }
    var nick: String
    var mode: MemberMode = .regular
    var isAway: Bool = false
}

// MARK: - Message

enum MessageKind: String, Codable {
    case message      // normal PRIVMSG
    case action       // /me — CTCP ACTION
    case notice       // NOTICE
    case server       // server numerics / info
    case whois        // WHOIS reply lines
    case join
    case part
    case quit
}

struct LinkPreview: Hashable {
    enum Kind { case link, image }
    var kind: Kind
    var title: String = ""
    var meta: String = ""
    var label: String = ""
    var dims: String = ""
}

struct Message: Identifiable, Hashable {
    let id: String
    var kind: MessageKind
    var nick: String = ""
    var text: String = ""
    var timestamp: Date = .now
    var preview: LinkPreview? = nil

    var isJoinPartQuit: Bool { kind == .join || kind == .part || kind == .quit }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: timestamp)
    }
}

// MARK: - Conversation

enum ConversationKind: String, Codable {
    case channel
    case directMessage
    case server   // server console / status window
}

struct Conversation: Identifiable, Hashable {
    let id: String                 // "<networkID>/<name>"
    var kind: ConversationKind
    var name: String               // "#coder-com", "catnip", network name for server
    var topic: String = ""
    var members: [Member] = []
    var messages: [Message] = []
    var unread: Int = 0
    var mentions: Int = 0
    var firstUnreadID: String? = nil
    var isMuted: Bool = false

    // Active channel modes (best-effort: updated optimistically on set and from
    // MODE events on the live transport).
    var activeModes: Set<String> = []
    var modeLimit: Int? = nil
    var modeKey: String? = nil
    var bans: [String] = []

    var memberCount: Int { kind == .channel ? max(members.count, declaredMemberCount) : 0 }
    var declaredMemberCount: Int = 0

    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Channel list (/list results)

struct ChannelListItem: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var users: Int
    var topic: String
}

// MARK: - Network

struct Network: Identifiable, Hashable {
    let id: String                 // "undernet"
    var name: String               // "Undernet"
    var server: String             // "Ann-Arbor.MI.US.Undernet.org"
    var nick: String               // current nick on this network
    var state: ConnectionState
    var isExpanded: Bool = true
    var conversationIDs: [String] = []

    var serverConsoleID: String { "\(id)/$server" }

    static func == (lhs: Network, rhs: Network) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Nick coloring (stable hash → palette)

enum NickColor {
    private static let hues: [Double] = [6, 20, 33, 46, 140, 165, 188, 208, 232, 262, 288, 318, 338]

    static func color(for nick: String, dark: Bool) -> Color {
        var h: UInt32 = 0
        for scalar in nick.unicodeScalars { h = (h &* 31 &+ scalar.value) }
        let hue = hues[Int(h % UInt32(hues.count))]
        return Color(hue: hue / 360.0,
                     saturation: dark ? 0.68 : 0.58,
                     brightness: dark ? 0.70 : 0.40)
    }

    static func monogram(_ name: String) -> String {
        let trimmed = name.drop { $0 == "#" || $0 == "&" }
        return String(trimmed.first ?? Character("?")).uppercased()
    }
}

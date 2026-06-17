import Foundation
import Observation

@MainActor
@Observable
final class ChannelModel: Identifiable {
    enum Kind: Sendable { case server, channel, dm }

    let id = UUID()
    let name: String
    let kind: Kind
    var topic: String = ""
    var lines: [ChatLine] = []
    var members: [Member] = []
    var unread: Int = 0
    var hasMention: Bool = false

    init(name: String, kind: Kind, topic: String = "") {
        self.name = name
        self.kind = kind
        self.topic = topic
    }

    /// Members sorted op → voice → plain, alphabetically within each rank.
    var sortedMembers: [Member] {
        members.sorted { a, b in
            if a.prefix != b.prefix { return a.prefix < b.prefix }
            return a.nick.localizedCaseInsensitiveCompare(b.nick) == .orderedAscending
        }
    }

    var symbolName: String {
        switch kind {
        case .server:  return "bonjour"
        case .channel: return "number"
        case .dm:      return "at"
        }
    }

    func append(_ line: ChatLine, isActive: Bool) {
        lines.append(line)
        if !isActive {
            unread += 1
            if line.isMention || kind == .dm { hasMention = true }
        }
    }

    func markRead() {
        unread = 0
        hasMention = false
    }
}

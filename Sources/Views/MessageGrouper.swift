import Foundation

/// Pure transform: a conversation's flat `[Message]` becomes display rows for
/// the message list — grouping consecutive messages by author, coalescing
/// join/part/quit into one collapsible event group, and inserting the unread
/// divider. Kept out of the view so it stays unit-testable.
enum MessageRow: Identifiable {
    case divider(id: String)
    case events(id: String, summary: String, lines: [String], group: [Message])
    case message(Message, showHeader: Bool, isMention: Bool)
    case action(Message)
    case notice(Message)
    case server(Message)

    var id: String {
        switch self {
        case .divider(let id): return "div-\(id)"
        case .events(let id, _, _, _): return "evt-\(id)"
        case .message(let m, _, _): return m.id
        case .action(let m): return m.id
        case .notice(let m): return m.id
        case .server(let m): return m.id
        }
    }
}

enum MessageGrouper {

    static func rows(for conv: Conversation, selfNick: String, keywords: [String] = [], searchQuery: String?) -> [MessageRow] {
        let highlightWords = ([selfNick] + keywords).filter { !$0.isEmpty }
        func isHighlight(_ text: String) -> Bool {
            for w in highlightWords where text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: w))\\b",
                                                     options: [.regularExpression, .caseInsensitive]) != nil { return true }
            return false
        }
        var rows: [MessageRow] = []
        var eventBuffer: [Message] = []
        var previousNick: String?

        func flushEvents() {
            guard !eventBuffer.isEmpty else { return }
            let names = eventBuffer.prefix(3).map(\.nick)
            let extra = eventBuffer.count - names.count
            let joined = eventBuffer.filter { $0.kind == .join }.count
            let left = eventBuffer.count - joined
            var verbs: [String] = []
            if joined > 0 { verbs.append("\(joined) joined") }
            if left > 0 { verbs.append("\(left) left") }
            let summary = names.joined(separator: ", ")
                + (extra > 0 ? " +\(extra) others" : "")
                + "  ·  " + verbs.joined(separator: ", ")
            let lines = eventBuffer.map { m -> String in
                let verb = m.kind == .join ? "joined" : m.kind == .part ? "left" : "quit"
                return "*** \(m.nick) (\(m.text)) has \(verb)"
            }
            rows.append(.events(id: eventBuffer[0].id, summary: summary, lines: lines, group: eventBuffer))
            eventBuffer.removeAll()
        }

        let q = (searchQuery?.isEmpty == false) ? searchQuery!.lowercased() : nil

        for m in conv.messages {
            if m.isJoinPartQuit {
                if q == nil { eventBuffer.append(m) }   // hide join/part while searching
                continue
            }
            flushEvents()

            if let q, !m.text.lowercased().contains(q) { continue }

            if conv.firstUnreadID == m.id, conv.kind != .server, q == nil {
                rows.append(.divider(id: m.id))
            }

            switch m.kind {
            case .action:
                rows.append(.action(m)); previousNick = nil
            case .notice:
                rows.append(.notice(m)); previousNick = nil
            case .server, .whois:
                rows.append(.server(m)); previousNick = nil
            case .message:
                let grouped = previousNick == m.nick
                let isMention = m.nick != selfNick && isHighlight(m.text)
                rows.append(.message(m, showHeader: !grouped, isMention: isMention))
                previousNick = m.nick
            default:
                break
            }
        }
        flushEvents()
        return rows
    }
}

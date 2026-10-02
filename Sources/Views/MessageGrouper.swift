import Foundation

/// Pure transform: a conversation's flat `[Message]` becomes display rows for
/// the message list — grouping consecutive messages by author, coalescing
/// join/part/quit into one collapsible event group, and inserting the unread
/// divider. Kept out of the view so it stays unit-testable.
// Equatable is load-bearing: without it SwiftUI can't prove rows unchanged,
// so every incoming message re-rendered and re-measured EVERY row in the
// scrollback — O(rows) layout per message, sluggish by a few hundred lines.
enum MessageRow: Identifiable, Equatable {
    case divider(id: String)
    case day(id: String, label: String)
    case events(id: String, summary: String, lines: [String], group: [Message])
    case message(Message, showHeader: Bool, isMention: Bool)
    case action(Message)
    case notice(Message)
    case server(Message)

    var id: String {
        switch self {
        case .divider(let id): return "div-\(id)"
        case .day(let id, _): return "day-\(id)"
        case .events(let id, _, _, _): return "evt-\(id)"
        case .message(let m, _, _): return m.id
        case .action(let m): return m.id
        case .notice(let m): return m.id
        case .server(let m): return m.id
        }
    }
}

enum MessageGrouper {

    static func rows(for conv: Conversation, selfNick: String, keywords: [String] = [], searchQuery: String?,
                     now: Date = .now, calendar: Calendar = .current) -> [MessageRow] {
        // ONE compiled regex for the whole pass. range(of:.regularExpression)
        // recompiled the pattern per message per word — at the 2000-message
        // scrollback cap that meant thousands of regex compiles on the main
        // thread for every incoming message.
        let highlightWords = ([selfNick] + keywords).filter { !$0.isEmpty }
        let highlightRegex: NSRegularExpression? = highlightWords.isEmpty ? nil :
            try? NSRegularExpression(
                pattern: "\\b(?:" + highlightWords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b",
                options: [.caseInsensitive])
        func isHighlight(_ text: String) -> Bool {
            guard let highlightRegex else { return false }
            return highlightRegex.firstMatch(in: text,
                                             range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }
        var rows: [MessageRow] = []
        var eventBuffer: [Message] = []
        var previousNick: String?
        var lastDayKey: String?

        func noteDay(_ date: Date, id: String) {
            let key = DayChip.key(for: date, calendar: calendar)
            guard key != lastDayKey else { return }
            lastDayKey = key
            rows.append(.day(id: id, label: DayChip.label(for: date, now: now, calendar: calendar)))
            previousNick = nil
        }

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
            // m.text carries the REASON ("left (bye)", "quit (ping timeout)"),
            // not a hostmask — render it as the tail of the sentence so part /
            // quit reasons are actually readable.
            let lines = eventBuffer.map { m -> String in
                let tail = m.text.isEmpty
                    ? (m.kind == .join ? "joined" : m.kind == .part ? "left" : "quit")
                    : m.text
                return "*** \(m.nick) has \(tail)"
            }
            rows.append(.events(id: eventBuffer[0].id, summary: summary, lines: lines, group: eventBuffer))
            eventBuffer.removeAll()
        }

        let q = (searchQuery?.isEmpty == false) ? searchQuery!.lowercased() : nil

        for m in conv.messages {
            if m.isJoinPartQuit {
                if q == nil {
                    let key = DayChip.key(for: m.timestamp, calendar: calendar)
                    if !eventBuffer.isEmpty, key != lastDayKey { flushEvents() }
                    noteDay(m.timestamp, id: m.id)
                    eventBuffer.append(m)
                }
                continue
            }
            flushEvents()

            if let q, !m.text.lowercased().contains(q) { continue }

            noteDay(m.timestamp, id: m.id)

            if conv.firstUnreadID == m.id, conv.kind != .server, q == nil {
                rows.append(.divider(id: m.id))
            }

            switch m.kind {
            case .action:
                rows.append(.action(m)); previousNick = nil
            case .notice:
                rows.append(.notice(m)); previousNick = nil
            case .server, .whois, .kick:
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

import Foundation

/// `@nick` tokens in message text. An email (`name@host`) is not a mention:
/// the character before `@` has to be outside the nick alphabet.
enum MentionSpans {
    static func isNickCharacter(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return "[]\\`_^{|}-".contains(c)
    }

    static func ranges(in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "@" {
                let beforeOK = i == text.startIndex || !isNickCharacter(text[text.index(before: i)])
                let next = text.index(after: i)
                if beforeOK, next < text.endIndex, isNickCharacter(text[next]) {
                    var end = next
                    while end < text.endIndex, isNickCharacter(text[end]) {
                        end = text.index(after: end)
                    }
                    found.append(i..<end)
                    i = end
                    continue
                }
            }
            i = text.index(after: i)
        }
        return found
    }
}

/// Day stamps for the scrollback. "Today" and "Yesterday" follow `now`;
/// anything older is a calendar date.
enum DayChip {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdy")
        return formatter.string(from: date)
    }
}

/// What Return should actually send. IRC is one line per message; a paste
/// with newlines becomes several messages so the flood pacer can space them.
enum OutgoingLines {
    static func lines(in raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

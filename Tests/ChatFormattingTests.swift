import XCTest
@testable import RelayIRC

final class ChatFormattingTests: XCTestCase {

    func testMentionSpansFindNicksAndSkipEmails() {
        let hey = MentionSpans.ranges(in: "hey @alice")
        XCTAssertEqual(hey.map { String("hey @alice"[$0]) }, ["@alice"])

        XCTAssertTrue(MentionSpans.ranges(in: "mail a@b.com").isEmpty)
        XCTAssertTrue(MentionSpans.ranges(in: "@").isEmpty)
        XCTAssertTrue(MentionSpans.ranges(in: "").isEmpty)

        let two = "(@zig) @bob"
        XCTAssertEqual(MentionSpans.ranges(in: two).map { String(two[$0]) }, ["@zig", "@bob"])

        let possessive = "hey @alice's idea"
        XCTAssertEqual(MentionSpans.ranges(in: possessive).map { String(possessive[$0]) }, ["@alice"])
    }

    func testDayChipTodayYesterdayAndOlder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = date(2026, 10, 2, calendar)
        XCTAssertEqual(DayChip.label(for: now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(DayChip.label(for: date(2026, 10, 1, calendar), now: now, calendar: calendar), "Yesterday")
        let older = DayChip.label(for: date(2026, 9, 15, calendar), now: now, calendar: calendar)
        XCTAssertFalse(older == "Today" || older == "Yesterday")
        XCTAssertTrue(older.contains("15"))
    }

    func testGrouperSplitsDaysAndRestartsTheSpeakerGroup() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = date(2026, 10, 2, calendar)
        var conv = Conversation(id: "n/#c", kind: .channel, name: "#c")
        var yesterday = Message(id: "y", kind: .message, nick: "a", text: "night")
        yesterday.timestamp = date(2026, 10, 1, calendar)
        var today = Message(id: "t", kind: .message, nick: "a", text: "morning")
        today.timestamp = now
        conv.messages = [yesterday, today]

        let rows = MessageGrouper.rows(for: conv, selfNick: "me", searchQuery: nil, now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 4)
        guard case .day(_, "Yesterday") = rows[0],
              case .message(_, true, _) = rows[1],
              case .day(_, "Today") = rows[2],
              case .message(_, true, _) = rows[3] else {
            XCTFail("expected Yesterday, a header, Today, and a fresh header, got \(rows)")
            return
        }
    }

    func testOutgoingLinesSplitPasteAndDropBlanks() {
        XCTAssertEqual(OutgoingLines.lines(in: "one"), ["one"])
        XCTAssertEqual(OutgoingLines.lines(in: "  a \r\n\n b \n"), ["a", "b"])
        XCTAssertTrue(OutgoingLines.lines(in: "\n").isEmpty)
    }

    func testEmojiInsertsAtTheCaret() {
        let applied = ComposerTokens.insert("🔥", text: "hi", caretUTF16: 2)
        XCTAssertEqual(applied.text, "hi🔥")
        XCTAssertEqual(applied.caretUTF16, "hi🔥".utf16.count)

        let mid = ComposerTokens.insert("⭐", text: "ab", caretUTF16: 1)
        XCTAssertEqual(mid.text, "a⭐b")
        XCTAssertEqual(mid.caretUTF16, "a⭐".utf16.count)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 15
        parts.calendar = calendar
        return calendar.date(from: parts)!
    }
}

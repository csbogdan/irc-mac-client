import XCTest
@testable import RelayIRC

final class IRCParserTests: XCTestCase {

    func testSimplePrivmsg() {
        let m = IRCParser.parse(":nick!user@host PRIVMSG #chan :hello world")
        XCTAssertEqual(m?.command, "PRIVMSG")
        XCTAssertEqual(m?.sourceNick, "nick")
        XCTAssertEqual(m?.params.first, "#chan")
        XCTAssertEqual(m?.trailing, "hello world")
    }

    func testMessageTags() {
        let m = IRCParser.parse("@time=2024-01-01T00:00:00.000Z;account=bob :bob!b@h PRIVMSG #c :hi")
        XCTAssertEqual(m?.tags["account"], "bob")
        XCTAssertEqual(m?.tags["time"], "2024-01-01T00:00:00.000Z")
        XCTAssertEqual(m?.sourceNick, "bob")
    }

    func testTagEscapes() {
        let m = IRCParser.parse("@msgid=a\\sb\\:c :x!y@z NOTICE * :ok")
        XCTAssertEqual(m?.tags["msgid"], "a b;c")
    }

    /// `\\` is one escape. The character after it is literal, so `\\s` is a
    /// backslash followed by s — the bug the old sequential replacements had.
    func testTagEscapeIsOneLeftToRightPass() {
        let slashS = IRCParser.parse("@msgid=a\\\\sb :x!y@z NOTICE * :ok")
        XCTAssertEqual(slashS?.tags["msgid"], "a\\sb")

        let slashColon = IRCParser.parse("@msgid=a\\\\:b :x!y@z NOTICE * :ok")
        XCTAssertEqual(slashColon?.tags["msgid"], "a\\:b")

        // Unrecognized \x keeps x. A trailing backslash is dropped. The space
        // ends the tag value.
        let other = IRCParser.parse("@msgid=a\\xb\\ :x!y@z NOTICE * :ok")
        XCTAssertEqual(other?.tags["msgid"], "axb")

        let breaks = IRCParser.parse("@msgid=a\\nb\\rc :x!y@z NOTICE * :ok")
        XCTAssertEqual(breaks?.tags["msgid"], "a\nb\rc")
    }

    func testNumericServerLine() {
        let m = IRCParser.parse(":server.name 001 mynick :Welcome to the network")
        XCTAssertEqual(m?.command, "001")
        XCTAssertNil(m?.sourceNick)            // server prefix, not a user
        XCTAssertEqual(m?.trailing, "Welcome to the network")
    }

    func testPing() {
        let m = IRCParser.parse("PING :irc.example.org")
        XCTAssertEqual(m?.command, "PING")
        XCTAssertEqual(m?.trailing, "irc.example.org")
    }

    func testSerializeRoundTrip() {
        let line = IRCParser.serialize(command: "PRIVMSG", params: ["#chan", "hello there"])
        XCTAssertEqual(line, "PRIVMSG #chan :hello there\r\n")
    }

    func testGrouperCoalescesJoins() {
        var conv = Conversation(id: "n/#c", kind: .channel, name: "#c")
        conv.messages = [
            Message(id: "1", kind: .join, nick: "a", text: "~a@h"),
            Message(id: "2", kind: .join, nick: "b", text: "~b@h"),
            Message(id: "3", kind: .message, nick: "a", text: "hi"),
        ]
        let rows = MessageGrouper.rows(for: conv, selfNick: "me", searchQuery: nil)
        // One coalesced event group + one message row.
        XCTAssertEqual(rows.count, 2)
        if case .events(_, _, let lines, _) = rows[0] {
            XCTAssertEqual(lines.count, 2)
        } else { XCTFail("expected event group first") }
    }
}

import XCTest
@testable import RelayIRC

final class ComposerTokensTests: XCTestCase {

    func testMentionQueryAtEnd() {
        let text = "hello @bo"
        let q = ComposerTokens.mentionQuery(text: text, caretUTF16: text.utf16.count)
        XCTAssertEqual(q?.query, "bo")
        XCTAssertEqual(q.map { String(text[$0.range]) }, "@bo")
    }

    func testBareAtListsEveryone() {
        let text = "@"
        let q = ComposerTokens.mentionQuery(text: text, caretUTF16: 1)
        XCTAssertEqual(q?.query, "")
    }

    func testEmailIsNotAMention() {
        let text = "mail me at dev@relay.test"
        XCTAssertNil(ComposerTokens.mentionQuery(text: text, caretUTF16: text.utf16.count))
    }

    func testSpaceEndsTheMentionToken() {
        let text = "@alice "
        XCTAssertNil(ComposerTokens.mentionQuery(text: text, caretUTF16: text.utf16.count))
    }

    func testMentionKeepsTextAfterTheCaret() {
        let text = "hey @al there"
        let caret = ("hey @al" as NSString).length
        let q = ComposerTokens.mentionQuery(text: text, caretUTF16: caret)!
        let applied = ComposerTokens.replacing(
            text: text, range: q.range,
            with: ComposerTokens.mentionReplacement(nick: "alice", text: text, range: q.range))
        XCTAssertEqual(applied.text, "hey @alice there")
        XCTAssertEqual(applied.caretUTF16, ("hey @alice" as NSString).length)
    }

    func testClickMentionSpacesItselfOffThePreviousWord() {
        let applied = ComposerTokens.mentionInsertion(nick: "alice", text: "hello", caretUTF16: 5)
        XCTAssertEqual(applied.text, "hello @alice ")
    }

    func testClickMentionAtStartHasNoLeadingSpace() {
        let applied = ComposerTokens.mentionInsertion(nick: "alice", text: "", caretUTF16: 0)
        XCTAssertEqual(applied.text, "@alice ")
        XCTAssertEqual(applied.caretUTF16, applied.text.utf16.count)
    }
}

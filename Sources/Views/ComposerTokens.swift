import Foundation

/// Caret-relative edits for the composer. Pure so paste, Tab, and @mentions
/// can be tested without an AppKit text view. Offsets are UTF-16, matching
/// `NSTextView.selectedRange`.
enum ComposerTokens {

    static func index(in text: String, utf16Offset: Int) -> String.Index {
        let view = text.utf16
        let clamped = min(max(0, utf16Offset), view.count)
        let utf16Index = view.index(view.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: text) ?? text.endIndex
    }

    /// The whitespace-delimited token touching the caret, caret not included.
    /// Nil when the caret is at the start of a token (nothing typed yet).
    static func tokenBeforeCaret(text: String, caret: String.Index) -> (range: Range<String.Index>, token: String)? {
        guard caret > text.startIndex else { return nil }
        let before = text[..<caret]
        guard let last = before.last, !last.isWhitespace else { return nil }
        let start = before.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        guard start < caret else { return nil }
        return (start..<caret, String(text[start..<caret]))
    }

    /// `@query` immediately before the caret. `foo@bar` is an address, not a mention.
    static func mentionQuery(text: String, caretUTF16: Int) -> (range: Range<String.Index>, query: String)? {
        let caret = index(in: text, utf16Offset: caretUTF16)
        guard let (range, token) = tokenBeforeCaret(text: text, caret: caret),
              token.hasPrefix("@") else { return nil }
        return (range, String(token.dropFirst()))
    }

    /// `@nick` plus a trailing space, unless the next character is already whitespace.
    static func mentionReplacement(nick: String, text: String, range: Range<String.Index>) -> String {
        let followedBySpace = range.upperBound < text.endIndex && text[range.upperBound].isWhitespace
        return followedBySpace ? "@\(nick)" : "@\(nick) "
    }

    static func replacing(text: String, range: Range<String.Index>, with insertion: String) -> (text: String, caretUTF16: Int) {
        let prefix = text[..<range.lowerBound]
        let suffix = text[range.upperBound...]
        let result = String(prefix) + insertion + String(suffix)
        return (result, (String(prefix) + insertion).utf16.count)
    }

    /// `@nick ` at the caret. A leading space is added when the caret sits
    /// against another word, so a click-to-mention doesn't glue on.
    static func mentionInsertion(nick: String, text: String, caretUTF16: Int) -> (text: String, caretUTF16: Int) {
        let caret = index(in: text, utf16Offset: caretUTF16)
        var snippet = "@\(nick) "
        if caret > text.startIndex, !text[text.index(before: caret)].isWhitespace {
            snippet = " " + snippet
        }
        return replacing(text: text, range: caret..<caret, with: snippet)
    }

    /// Drop a snippet (an emoji, usually) at the caret.
    static func insert(_ snippet: String, text: String, caretUTF16: Int) -> (text: String, caretUTF16: Int) {
        let caret = index(in: text, utf16Offset: caretUTF16)
        return replacing(text: text, range: caret..<caret, with: snippet)
    }
}

import SwiftUI

/// Message composer with slash-command autocomplete, Tab nick completion,
/// and @mention picking. The field is an NSTextView so copy and paste work.
struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var caretUTF16 = 0
    @State private var fieldHeight: CGFloat = 32
    @State private var focusNonce = 0
    @State private var slashIndex = 0
    @State private var mentionIndex = 0
    /// `@query` the user dismissed with Escape, so the list stays closed
    /// until the token changes.
    @State private var suppressedMention: String?
    @State private var completion: NickCompletion?
    @State private var historyIndex: Int?
    @State private var stashedDraft = ""
    @State private var emojiOpen = false

    private let emoji = ["😀", "😂", "🥹", "😍", "😎", "🤔", "😅", "😭",
                         "😉", "🙃", "🤝", "👍", "👎", "🔥", "❤️", "🎉",
                         "👀", "💯", "✅", "🚀", "☕", "🎸", "🍿", "👋",
                         "🙏", "💀", "⭐", "🍻"]

    private struct NickCompletion {
        var base: String
        var matches: [String]
        var index: Int
        var result: String
        /// Text after the completed token, kept intact while Tab cycles.
        var tail: String
    }

    private struct Command { let cmd: String; let args: String; let desc: String }
    private let commands: [Command] = [
        .init(cmd: "join", args: "#channel [key]", desc: "Join a channel"),
        .init(cmd: "msg", args: "<nick> <text>", desc: "Send a private message"),
        .init(cmd: "me", args: "<action>", desc: "Send an action"),
        .init(cmd: "nick", args: "<newnick>", desc: "Change your nickname"),
        .init(cmd: "topic", args: "<text>", desc: "Set the channel topic"),
        .init(cmd: "whois", args: "<nick>", desc: "Look up a user"),
        .init(cmd: "ignore", args: "<nick>", desc: "Hide someone (client-side)"),
        .init(cmd: "silence", args: "<nick|+mask>", desc: "Server-side ignore (Undernet)"),
        .init(cmd: "query", args: "<nick>", desc: "Open a private chat"),
        .init(cmd: "part", args: "", desc: "Leave the current channel"),
        .init(cmd: "cycle", args: "[#channel]", desc: "Leave and re-join (keeps the window)"),
        .init(cmd: "quit", args: "<message>", desc: "Disconnect from the server"),
    ]

    private var slashOpen: Bool { draft.hasPrefix("/") && !draft.contains(" ") }
    private var slashMatches: [Command] {
        let q = draft.dropFirst().lowercased()
        return commands.filter { $0.cmd.hasPrefix(q) }
    }

    private var mentionQuery: (range: Range<String.Index>, query: String)? {
        ComposerTokens.mentionQuery(text: draft, caretUTF16: caretUTF16)
    }

    private var mentionMatches: [String] {
        guard let q = mentionQuery else { return [] }
        if suppressedMention == "@\(q.query)" { return [] }
        return model.mentionMatches(prefix: q.query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let completion { completionChips(completion) }
            if slashOpen, !slashMatches.isEmpty { slashPopover }
            if completion == nil, !slashOpen, !mentionMatches.isEmpty { mentionPopover }

            HStack(alignment: .bottom, spacing: 8) {
                ComposerTextView(
                    text: $draft,
                    caretUTF16: $caretUTF16,
                    placeholder: placeholder,
                    focusNonce: focusNonce,
                    measuredHeight: $fieldHeight,
                    onSubmit: submitOrComplete,
                    onTab: handleTab,
                    onVertical: handleVertical,
                    onEscape: dismissMention
                )
                .frame(height: fieldHeight)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .relayGlass(cornerRadius: Theme.composerCornerRadius)
                .onChange(of: draft) { _, new in
                    // Keep cycle state alive when the change came from Tab
                    // completion itself — reset only on real typing.
                    if new != completion?.result { completion = nil }
                    slashIndex = 0
                }
                .onChange(of: mentionQuery?.query) { _, _ in mentionIndex = 0 }

                Button { emojiOpen.toggle() } label: {
                    composerGlyph("face.smiling")
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .help("Emoji")
                .popover(isPresented: $emojiOpen, arrowEdge: .top) { emojiPopover }

                Menu {
                    ArtMenu { model.sendArt($0) }
                } label: {
                    composerGlyph("paintpalette")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 32, height: 32, alignment: .center)
                .help("Send ASCII art")

                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .relayGlassCircle(tint: Theme.mention)
            }

            HStack(spacing: 16) {
                hint("↩", "send"); hint("⇧↩", "newline"); hint("⇥", "complete"); hint("@", "mention"); hint("😀", "emoji"); hint("/", "commands")
            }
            .padding(.top, 6).padding(.horizontal, 4)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        // The composer should just BE focused — on open, on every conversation
        // switch, and whenever the app comes to the front. No hunting for a
        // small box with the mouse.
        // Focus on open, on every conversation switch, and when the app comes
        // forward. A nonce — not a sticky focus flag — so selecting text in
        // the scrollback is allowed to take the keyboard afterwards.
        .onAppear { focusNonce += 1 }
        .onChange(of: model.selectedID) { _, _ in focusNonce += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            focusNonce += 1
        }
        .onChange(of: model.composerInsertion) { _, insertion in
            guard let insertion else { return }
            let applied = ComposerTokens.mentionInsertion(nick: insertion, text: draft, caretUTF16: caretUTF16)
            draft = applied.text
            caretUTF16 = applied.caretUTF16
            model.composerInsertion = nil
            focusNonce += 1
        }
    }

    private var placeholder: String {
        guard let c = model.selectedConversation else { return "Message" }
        switch c.kind {
        case .directMessage: return "Message \(c.name)"
        case .server: return "Type a command…"
        case .channel: return "Message \(c.name)"
        }
    }

    /// Same box and weight for the composer tools, so a menu button and a
    /// plain button sit on one line.
    private func composerGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func hint(_ k: String, _ label: String) -> some View {
        HStack(spacing: 4) { Text(k); Text(label) }
            .font(.system(size: 11)).foregroundStyle(.tertiary)
    }

    // MARK: Slash popover

    private var slashPopover: some View {
        VStack(spacing: 2) {
            ForEach(Array(slashMatches.enumerated()), id: \.element.cmd) { i, c in
                HStack(spacing: 10) {
                    Text("/\(c.cmd)").font(.system(size: 12.5, design: .monospaced))
                    Text(c.args).font(.system(size: 11.5)).opacity(0.65)
                    Spacer()
                    Text(c.desc).font(.system(size: 11.5)).opacity(0.65)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(i == slashIndex ? AnyShapeStyle(Theme.mention) : AnyShapeStyle(.clear)))
                .foregroundStyle(i == slashIndex ? .white : .primary)
                .contentShape(Rectangle())
                .onTapGesture { draft = "/\(c.cmd) " }
            }
        }
        .padding(5)
        .relayGlass(cornerRadius: 14)
        .padding(.bottom, 8)
    }

    private var emojiPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 2), count: 7), spacing: 2) {
                ForEach(emoji, id: \.self) { symbol in
                    Button { insertEmoji(symbol) } label: {
                        Text(symbol).font(.system(size: 20)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("More Characters…") {
                emojiOpen = false
                NSApp.orderFrontCharacterPalette(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 236)
    }

    private func insertEmoji(_ symbol: String) {
        let applied = ComposerTokens.insert(symbol, text: draft, caretUTF16: caretUTF16)
        draft = applied.text
        caretUTF16 = applied.caretUTF16
        emojiOpen = false
        focusNonce += 1
    }

    private var mentionPopover: some View {
        VStack(spacing: 2) {
            ForEach(Array(mentionMatches.enumerated()), id: \.element) { i, nick in
                HStack(spacing: 8) {
                    Text("@\(nick)").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(i == mentionIndex ? AnyShapeStyle(Theme.mention) : AnyShapeStyle(.clear)))
                .foregroundStyle(i == mentionIndex ? .white : .primary)
                .contentShape(Rectangle())
                .onTapGesture { acceptMention(nick) }
            }
        }
        .padding(5)
        .relayGlass(cornerRadius: 14)
        .padding(.bottom, 8)
    }

    private func completionChips(_ c: NickCompletion) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(c.matches.enumerated()), id: \.element) { i, nick in
                Text(nick)
                    .font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Capsule().fill(i == c.index ? AnyShapeStyle(Theme.mention) : AnyShapeStyle(.quaternary)))
                    .foregroundStyle(i == c.index ? .white : .secondary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Key handling

    /// Return sends, unless an @mention list is open — then it inserts the
    /// highlighted nick instead of posting a half-typed mention.
    private func submitOrComplete() {
        if !mentionMatches.isEmpty {
            acceptMention(mentionMatches[min(mentionIndex, mentionMatches.count - 1)])
            return
        }
        send()
    }

    private func handleTab() -> Bool {
        if slashOpen {
            let m = slashMatches
            if !m.isEmpty {
                draft = "/\(m[min(slashIndex, m.count - 1)].cmd) "
                caretUTF16 = draft.utf16.count
            }
            return true
        }
        if !mentionMatches.isEmpty {
            acceptMention(mentionMatches[min(mentionIndex, mentionMatches.count - 1)])
            return true
        }
        completeNick()
        return true
    }

    private func handleVertical(_ dir: Int) -> Bool {
        if slashOpen { return moveSlash(dir) == .handled }
        if !mentionMatches.isEmpty {
            let n = mentionMatches.count
            mentionIndex = (mentionIndex + (dir < 0 ? -1 : 1) + n) % n
            return true
        }
        return recallHistory(dir) == .handled
    }

    private func dismissMention() -> Bool {
        guard let q = mentionQuery else { return false }
        suppressedMention = "@\(q.query)"
        mentionIndex = 0
        return true
    }

    private func acceptMention(_ nick: String) {
        guard let q = mentionQuery else { return }
        let applied = ComposerTokens.replacing(
            text: draft, range: q.range,
            with: ComposerTokens.mentionReplacement(nick: nick, text: draft, range: q.range))
        draft = applied.text
        caretUTF16 = applied.caretUTF16
        mentionIndex = 0
        suppressedMention = nil
    }

    private func moveSlash(_ d: Int) -> KeyPress.Result {
        let n = slashMatches.count
        guard n > 0 else { return .ignored }
        slashIndex = (slashIndex + d + n) % n
        return .handled
    }

    private func completeNick() {
        if let c = completion, draft == c.result {
            let idx = (c.index + 1) % c.matches.count
            let suffix = c.tail.isEmpty ? Self.completionSuffix(for: c.matches[idx], base: c.base) : ""
            let inserted = c.matches[idx] + suffix
            let result = c.base + inserted + c.tail
            draft = result
            caretUTF16 = (c.base + inserted).utf16.count
            completion = NickCompletion(base: c.base, matches: c.matches, index: idx, result: result, tail: c.tail)
            return
        }
        let caret = ComposerTokens.index(in: draft, utf16Offset: caretUTF16)
        guard let (range, token) = ComposerTokens.tokenBeforeCaret(text: draft, caret: caret),
              !token.hasPrefix("@") else { return }
        let matches = model.completions(for: token)
        guard !matches.isEmpty else { return }
        let base = String(draft[..<range.lowerBound])
        let tail = String(draft[range.upperBound...])
        let suffix = tail.isEmpty ? Self.completionSuffix(for: matches[0], base: base) : ""
        let applied = ComposerTokens.replacing(text: draft, range: range, with: matches[0] + suffix)
        draft = applied.text
        caretUTF16 = applied.caretUTF16
        completion = NickCompletion(base: base, matches: matches, index: 0, result: applied.text, tail: tail)
    }

    /// "nick: " at line start, "nick " mid-line; channels never get a colon.
    private static func completionSuffix(for candidate: String, base: String) -> String {
        if candidate.hasPrefix("#") || candidate.hasPrefix("&") { return " " }
        return base.trimmingCharacters(in: .whitespaces).isEmpty ? ": " : " "
    }

    /// ↑/↓ walk previously sent lines (mIRC-style). The in-progress draft is
    /// stashed on first ↑ and restored when you walk back past the newest line.
    private func recallHistory(_ dir: Int) -> KeyPress.Result {
        let h = model.inputHistory
        guard !h.isEmpty else { return .ignored }
        if dir < 0 {
            if historyIndex == nil { stashedDraft = draft; historyIndex = h.count - 1 }
            else if historyIndex! > 0 { historyIndex! -= 1 }
            draft = h[historyIndex!]
            caretUTF16 = draft.utf16.count
            return .handled
        } else {
            guard let i = historyIndex else { return .ignored }
            if i < h.count - 1 {
                historyIndex = i + 1
                draft = h[historyIndex!]
            } else {
                historyIndex = nil
                draft = stashedDraft
            }
            caretUTF16 = draft.utf16.count
            return .handled
        }
    }

    private func send() {
        model.submit(draft)
        draft = ""; caretUTF16 = 0; completion = nil; slashIndex = 0
        mentionIndex = 0; suppressedMention = nil
        historyIndex = nil; stashedDraft = ""
    }
}

import SwiftUI

/// Message composer with slash-command autocomplete and Tab nick completion.
struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var slashIndex = 0
    @State private var completion: NickCompletion?
    @FocusState private var focused: Bool

    private struct NickCompletion { var base: String; var matches: [String]; var index: Int; var result: String }

    private struct Command { let cmd: String; let args: String; let desc: String }
    private let commands: [Command] = [
        .init(cmd: "join", args: "#channel", desc: "Join a channel"),
        .init(cmd: "msg", args: "<nick> <text>", desc: "Send a private message"),
        .init(cmd: "me", args: "<action>", desc: "Send an action"),
        .init(cmd: "nick", args: "<newnick>", desc: "Change your nickname"),
        .init(cmd: "topic", args: "<text>", desc: "Set the channel topic"),
        .init(cmd: "whois", args: "<nick>", desc: "Look up a user"),
        .init(cmd: "query", args: "<nick>", desc: "Open a private chat"),
        .init(cmd: "part", args: "", desc: "Leave the current channel"),
        .init(cmd: "quit", args: "<message>", desc: "Disconnect from the server"),
    ]

    private var slashOpen: Bool { draft.hasPrefix("/") && !draft.contains(" ") }
    private var slashMatches: [Command] {
        let q = draft.dropFirst().lowercased()
        return commands.filter { $0.cmd.hasPrefix(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let completion { completionChips(completion) }
            if slashOpen, !slashMatches.isEmpty { slashPopover }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .font(.system(size: 13.5))
                    .focused($focused)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.composerCornerRadius).fill(.quaternary.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.composerCornerRadius).strokeBorder(.separator))
                    .onKeyPress(.tab) { handleTab() }
                    .onKeyPress(.return) { handleReturn() }
                    .onKeyPress(.upArrow) { slashOpen ? moveSlash(-1) : .ignored }
                    .onKeyPress(.downArrow) { slashOpen ? moveSlash(1) : .ignored }
                    .onChange(of: draft) { _, _ in completion = nil; slashIndex = 0 }

                Button { send() } label: {
                    Image(systemName: "arrow.up").fontWeight(.semibold).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.mention))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                hint("↩", "send"); hint("⇧↩", "newline"); hint("⇥", "complete"); hint("/", "commands")
            }
            .padding(.top, 6).padding(.horizontal, 4)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
    }

    private var placeholder: String {
        guard let c = model.selectedConversation else { return "Message" }
        switch c.kind {
        case .directMessage: return "Message \(c.name)"
        case .server: return "Type a command…"
        case .channel: return "Message \(c.name)"
        }
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
        .background(RoundedRectangle(cornerRadius: 11).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.separator))
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

    private func handleReturn() -> KeyPress.Result {
        // NSEvent modifierFlags check for Shift → newline; here Return sends.
        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
        send(); return .handled
    }

    private func handleTab() -> KeyPress.Result {
        if slashOpen {
            let m = slashMatches
            if !m.isEmpty { draft = "/\(m[min(slashIndex, m.count - 1)].cmd) " }
            return .handled
        }
        completeNick(); return .handled
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
            let suffix = c.base.trimmingCharacters(in: .whitespaces).isEmpty ? ": " : " "
            let result = c.base + c.matches[idx] + suffix
            draft = result; completion = NickCompletion(base: c.base, matches: c.matches, index: idx, result: result)
            return
        }
        let token = String(draft.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !token.isEmpty else { return }
        let matches = model.completions(for: token)
        guard !matches.isEmpty else { return }
        let base = String(draft.dropLast(token.count))
        let suffix = base.trimmingCharacters(in: .whitespaces).isEmpty ? ": " : " "
        let result = base + matches[0] + suffix
        draft = result
        completion = NickCompletion(base: base, matches: matches, index: 0, result: result)
    }

    private func send() {
        model.submit(draft)
        draft = ""; completion = nil; slashIndex = 0
    }
}

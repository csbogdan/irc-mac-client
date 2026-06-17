import SwiftUI

struct ComposerView: View {
    @Bindable var channel: ChannelModel
    let network: NetworkModel?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(channel.name)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(draft.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(draft.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(10)
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let network else { return }
        draft = ""

        if text.hasPrefix("/") {
            handleCommand(text, network: network)
        } else {
            network.send("PRIVMSG \(channel.name) :\(text)")
        }
    }

    /// Minimal client-side slash-command handling.
    private func handleCommand(_ raw: String, network: NetworkModel) {
        let parts = raw.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts.first?.lowercased() ?? ""
        let argument = parts.count > 1 ? parts[1] : ""

        switch command {
        case "me":
            network.send("PRIVMSG \(channel.name) :\u{01}ACTION \(argument)\u{01}")
        case "join", "j":
            network.send("JOIN \(argument)")
        case "part":
            network.send("PART \(argument.isEmpty ? channel.name : argument)")
        case "msg":
            let sub = argument.split(separator: " ", maxSplits: 1).map(String.init)
            if sub.count == 2 { network.send("PRIVMSG \(sub[0]) :\(sub[1])") }
        case "nick":
            network.send("NICK \(argument)")
        case "topic":
            network.send("TOPIC \(channel.name) :\(argument)")
        case "whois":
            network.send("WHOIS \(argument)")
        case "quit":
            network.send("QUIT :\(argument.isEmpty ? "Leaving" : argument)")
        default:
            network.send(String(raw.dropFirst()))   // pass raw command through
        }
    }
}

import SwiftUI

/// Member list (detail pane): grouped by Operators / Voiced / Members with
/// presence dots, mode glyphs and a per-member context menu. A real List, so
/// rows select on click and highlight natively under right-click.
struct MemberListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var selectedNick: String?

    private var conv: Conversation? { model.selectedConversation }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("MEMBERS").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                Text("\(conv?.memberCount ?? 0) online").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)
            Divider()

            List(selection: $selectedNick) {
                group("Operators", members(.op))
                group("Voiced", members(.voice))
                group("Members", members(.regular))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { nicks in
                if let nick = nicks.first { memberMenu(nick) }
            }
        }
        .background(.regularMaterial)
    }

    private func members(_ mode: MemberMode) -> [Member] {
        (conv?.members ?? [])
            .filter { $0.mode == mode }
            .sorted { $0.nick.lowercased() < $1.nick.lowercased() }
    }

    @ViewBuilder private func group(_ title: String, _ list: [Member]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { m in
                    MemberRow(member: m)
                        .tag(m.nick)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                }
            } header: {
                Text("\(title) — \(list.count)")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
    }

    /// Context menu for the right-clicked member — the row highlights natively.
    @ViewBuilder private func memberMenu(_ nick: String) -> some View {
        Button("Whois \(nick)") { model.whois(nick) }
        Button("Message \(nick)") { model.openDM(nick) }
        Menu("Send ASCII Art") { ArtMenu { model.sendArt($0, toNick: nick) } }
        Divider()
        Button("Give Op (+o)") { model.setMode(.op, nick: nick) }
        Button("Give Voice (+v)") { model.setMode(.voice, nick: nick) }
        Divider()
        Button("Kick \(nick)…", role: .destructive) { model.kickPrompt(nick) }
        Button("Ban \(nick)…", role: .destructive) { model.banPrompt(nick) }
        Divider()
        Button(model.isIgnored(nick) ? "Unignore \(nick)" : "Ignore \(nick)") { model.toggleIgnore(nick) }
        Button("Silence \(nick) (server-side)") { model.silence(nick) }
        Divider()
        Menu("Channel Service (X)") {
            Button("Op via X") { model.xOp(nick) }
            Button("Deop via X") { model.xDeop(nick) }
            Button("Voice via X") { model.xVoice(nick) }
            Button("Devoice via X") { model.xDevoice(nick) }
            Divider()
            Button("Kick via X…", role: .destructive) { model.xKick(nick) }
            Button("Ban via X…", role: .destructive) { model.xBan(nick) }
            Button("Unban via X…") { model.xUnban(nick) }
            Divider()
            Button("Access level") { model.xAccessUser(nick) }
            Button("Add to userlist…") { model.xAddUser(nick) }
            Button("Suspend…", role: .destructive) { model.xSuspend(nick) }
            Button("Remove from userlist", role: .destructive) { model.xRemUser(nick) }
        }
    }
}

private struct MemberRow: View {
    @Environment(AppModel.self) private var model
    let member: Member

    var body: some View {
        HStack(spacing: 7) {
            // Presence dot — filled when online, hollow ring when away.
            Circle()
                .strokeBorder(member.isAway ? Color.secondary : .clear, lineWidth: 1.5)
                .background(Circle().fill(member.isAway ? .clear : Theme.opGreen))
                .frame(width: 7, height: 7)
            Text(member.mode.glyph)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(member.mode == .op ? Theme.opGreen : Theme.voiceBlue)
                .frame(width: 9)
            Text(member.nick)
                .font(.system(size: 12.5))
                .fontWeight(member.nick == model.selfNick ? .semibold : .regular)
                .foregroundStyle(member.isAway ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .italic(member.isAway)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

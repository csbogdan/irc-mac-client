import SwiftUI

/// Member list (detail pane): grouped by Operators / Voiced / Members with
/// presence dots, mode glyphs and a per-member context menu.
struct MemberListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var conv: Conversation? { model.selectedConversation }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("MEMBERS").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                Text("\(conv?.memberCount ?? 0) online").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    group("Operators", members(.op))
                    group("Voiced", members(.voice))
                    group("Members", members(.regular))
                }
                .padding(.vertical, 6)
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
            Text("\(title) — \(list.count)")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 3)
            ForEach(list) { m in MemberRow(member: m) }
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
        .padding(.horizontal, 12).padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Whois \(member.nick)") { model.whois(member.nick) }
            Button("Message \(member.nick)") { model.openDM(member.nick) }
            Menu("Send ASCII Art") { ArtMenu { model.sendArt($0, toNick: member.nick) } }
            Divider()
            Button("Give Op (+o)") { model.setMode(.op, nick: member.nick) }
            Button("Give Voice (+v)") { model.setMode(.voice, nick: member.nick) }
            Divider()
            Button("Kick \(member.nick)…", role: .destructive) { model.kickPrompt(member.nick) }
            Button("Ban \(member.nick)…", role: .destructive) { model.banPrompt(member.nick) }
            Divider()
            Menu("Channel Service (X)") {
                Button("Op via X") { model.xOp(member.nick) }
                Button("Deop via X") { model.xDeop(member.nick) }
                Button("Voice via X") { model.xVoice(member.nick) }
                Button("Devoice via X") { model.xDevoice(member.nick) }
                Divider()
                Button("Kick via X…", role: .destructive) { model.xKick(member.nick) }
                Button("Ban via X…", role: .destructive) { model.xBan(member.nick) }
                Button("Unban via X…") { model.xUnban(member.nick) }
                Divider()
                Button("Access level") { model.xAccessUser(member.nick) }
                Button("Add to userlist…") { model.xAddUser(member.nick) }
                Button("Suspend…", role: .destructive) { model.xSuspend(member.nick) }
                Button("Remove from userlist", role: .destructive) { model.xRemUser(member.nick) }
            }
        }
    }
}

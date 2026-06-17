import SwiftUI

struct MemberListView: View {
    @Bindable var channel: ChannelModel
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section("\(channel.members.count) members") {
                ForEach(channel.sortedMembers) { member in
                    MemberRow(member: member)
                        .contextMenu {
                            Button("Message \(member.nick)") { openDM(member) }
                            Button("Whois \(member.nick)") {
                                app.selectedNetwork?.send("WHOIS \(member.nick)")
                            }
                            Divider()
                            Button("Op") { mode("+o", member) }
                            Button("Voice") { mode("+v", member) }
                            Button("Kick", role: .destructive) {
                                app.selectedNetwork?.send("KICK \(channel.name) \(member.nick)")
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
    }

    private func mode(_ flag: String, _ member: Member) {
        app.selectedNetwork?.send("MODE \(channel.name) \(flag) \(member.nick)")
    }

    private func openDM(_ member: Member) {
        guard let network = app.selectedNetwork else { return }
        let dm = network.channel(named: member.nick, kind: .dm)
        app.select(dm)
    }
}

private struct MemberRow: View {
    let member: Member

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = member.symbolName {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(member.prefix == .op ? Color.orange : Color.green)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(member.isAway ? Color.secondary : Color.green)
            }
            Text(member.nick)
                .foregroundStyle(member.isAway ? .secondary : .primary)
            Spacer()
        }
    }
}

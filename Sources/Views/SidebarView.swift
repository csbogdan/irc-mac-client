import SwiftUI

/// Source-list sidebar: one Section per network with a connection-state header,
/// channel/DM rows, unread/mention badges and context menus.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        List(selection: Binding<String?>(
            get: { model.selectedID },
            set: { if let id = $0 { model.select(id) } })
        ) {
            if model.networks.isEmpty {
                Text("No networks. Add one in Settings (⌘,).")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(model.networks) { net in
                Section {
                    ForEach(net.conversationIDs.compactMap { model.conversations[$0] }) { conv in
                        ConversationRow(conv: conv)
                            .tag(conv.id)
                    }
                } header: {
                    NetworkHeader(network: net)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct NetworkHeader: View {
    @Environment(AppModel.self) private var model
    let network: Network

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(network.state.dotColor)
                .frame(width: 7, height: 7)
                .opacity(network.state.isBusy ? 0.6 : 1)
            Text(network.name.uppercased())
                .font(.system(size: 11, weight: .bold))
            if !network.state.label.isEmpty {
                Text(network.state.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .textCase(.none)
            }
            Spacer()
            Button(network.state == .disconnected ? "Connect" : "Disconnect") {
                if network.state == .disconnected { model.connect(network.id) }
                else { model.disconnect(network.id) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
            .textCase(.none)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(network.serverConsoleID) }
    }
}

private struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let conv: Conversation

    var body: some View {
        HStack(spacing: 8) {
            switch conv.kind {
            case .channel:
                Text("#").foregroundStyle(.tertiary).frame(width: 14)
            case .directMessage:
                Circle()
                    .fill(NickColor.color(for: conv.name, dark: scheme == .dark))
                    .frame(width: 18, height: 18)
                    .overlay(Text(NickColor.monogram(conv.name))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white))
            case .server:
                Image(systemName: "terminal").foregroundStyle(.tertiary).frame(width: 14)
            }

            Text(conv.name)
                .fontWeight(conv.unread > 0 ? .semibold : .regular)
                .foregroundStyle(conv.isMuted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)

            Spacer(minLength: 4)

            // Red = nick/keyword mentions; blue = general traffic. DMs only blue.
            if conv.mentions > 0 { countBadge(conv.mentions, Color(red: 1.0, green: 0.23, blue: 0.19)) }
            let general = conv.unread - conv.mentions
            if general > 0 { countBadge(general, Theme.mention) }
        }
        .contextMenu { contextMenu }
    }

    private func countBadge(_ n: Int, _ color: Color) -> some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .frame(minWidth: 16)
            .background(Capsule().fill(color))
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Mark as Read") { model.markRead(conv.id) }
        if conv.kind == .channel {
            Button(conv.isMuted ? "Unmute Channel" : "Mute Channel") { model.toggleMute(conv.id) }
            Button("Copy Channel Name") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(conv.name, forType: .string)
            }
            Menu("Channel Service (X)") {
                Button("Channel Info") { model.xChannel("chaninfo", for: conv.id) }
                Button("Access List") { model.xChannel("access", for: conv.id) }
                Button("Ban List") { model.xChannel("banlist", for: conv.id) }
                Divider()
                Button("Invite Me") { model.xChannel("invite", for: conv.id) }
                Button("Op Me") { model.xChannel("op", for: conv.id) }
                Button("Deop Me") { model.xChannel("deop", for: conv.id) }
            }
            Divider()
            Button("Leave Channel", role: .destructive) { model.remove(conv.id) }
        } else if conv.kind == .directMessage {
            Button(conv.isMuted ? "Unmute" : "Mute") { model.toggleMute(conv.id) }
            Divider()
            Button("Close Conversation", role: .destructive) { model.remove(conv.id) }
        }
    }
}

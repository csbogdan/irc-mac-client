import SwiftUI

/// Source-list sidebar: one Section per network with a connection-state header,
/// channel/DM rows, unread/mention badges and context menus.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(
            get: { model.selectedID },
            set: { if let id = $0 { model.select(id) } })
        ) {
            ForEach(model.networks) { net in
                Section(isExpanded: Binding(
                    get: { net.isExpanded },
                    set: { _ in model.toggleNetwork(net.id) })
                ) {
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
        .safeAreaInset(edge: .top, spacing: 0) { EmptyView() }
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
            if model.isDemo(network.id) {
                Text("DEMO")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(.orange.opacity(0.25)))
                    .foregroundStyle(.orange)
                    .textCase(.none)
            }
            if !network.state.label.isEmpty {
                Text(network.state.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .textCase(.none)
            }
            Spacer()
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

            if conv.unread > 0 {
                Text("\(conv.unread)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(conv.mentions > 0 ? Theme.mention : Color.secondary.opacity(0.5)))
            }
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Mark as Read") { model.markRead(conv.id) }
        if conv.kind == .channel {
            Button("Set Topic…") { model.select(conv.id) }
            Button(conv.isMuted ? "Unmute Channel" : "Mute Channel") { model.toggleMute(conv.id) }
            Button("Copy Channel Name") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(conv.name, forType: .string)
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

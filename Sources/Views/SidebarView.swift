import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        List(selection: Binding(
            get: { app.selection },
            set: { id in
                if let id, let channel = channel(for: id) { app.select(channel) }
            })
        ) {
            ForEach(app.networks) { network in
                Section {
                    ForEach(network.channels) { channel in
                        ChannelRow(channel: channel)
                            .tag(channel.id)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(network.state.isOnline ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(network.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    app.add(ServerConfig(name: "New Network", host: "irc.example.net", nick: "bogdan"))
                } label: {
                    Label("Add Network", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }

    private func channel(for id: UUID) -> ChannelModel? {
        for network in app.networks {
            if let c = network.channels.first(where: { $0.id == id }) { return c }
        }
        return nil
    }
}

private struct ChannelRow: View {
    @Bindable var channel: ChannelModel

    var body: some View {
        Label {
            HStack {
                Text(displayName)
                    .fontWeight(channel.unread > 0 ? .semibold : .regular)
                Spacer()
                if channel.hasMention {
                    Text("\(channel.unread)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                } else if channel.unread > 0 {
                    Text("\(channel.unread)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: channel.symbolName)
                .foregroundStyle(channel.hasMention ? Color.accentColor : .secondary)
        }
    }

    private var displayName: String {
        switch channel.kind {
        case .channel: return channel.name
        case .dm:      return channel.name
        case .server:  return "Server"
        }
    }
}

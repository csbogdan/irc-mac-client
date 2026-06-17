import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var app = app

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let channel = app.selectedChannel {
                ChannelDetailView(channel: channel, network: app.selectedNetwork)
            } else {
                ContentUnavailableView("No Channel Selected",
                                       systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Pick a channel from the sidebar to start chatting."))
            }
        }
        .sheet(isPresented: $app.quickSwitcherPresented) {
            QuickSwitcherView()
        }
        .onChange(of: app.totalUnread) { _, new in
            app.notifications.updateDockBadge(unread: new)
        }
    }
}

/// Center + right panes for one channel: messages, composer, and member list.
struct ChannelDetailView: View {
    @Bindable var channel: ChannelModel
    let network: NetworkModel?
    @Environment(AppModel.self) private var app

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                MessageListView(channel: channel)
                Divider()
                ComposerView(channel: channel, network: network)
            }
            .frame(minWidth: 360)

            if app.memberListVisible && channel.kind == .channel {
                MemberListView(channel: channel)
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
            }
        }
        .navigationTitle(channel.name)
        .navigationSubtitle(channel.topic)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !channel.topic.isEmpty {
                    Text(channel.topic).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    app.quickSwitcherPresented = true
                } label: { Image(systemName: "magnifyingglass") }
                .help("Quick Switch (⌘K)")

                Button {
                    withAnimation { app.memberListVisible.toggle() }
                } label: { Image(systemName: "person.2") }
                .help("Toggle Member List")
                .disabled(channel.kind != .channel)
            }
        }
    }
}

import SwiftUI

/// Three-column shell: NavigationSplitView(sidebar, content, detail).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            HStack(spacing: 0) {
                ConversationView()
                if model.memberListVisible, model.selectedConversation?.kind == .channel {
                    Divider()
                    MemberListView()
                        .frame(width: 200)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.quickSwitcherOpen) { QuickSwitcherView() }
        .sheet(isPresented: $model.channelModesOpen) { ChannelModesView() }
        .sheet(isPresented: $model.xSettingsOpen) { XChannelSettingsView() }
        .sheet(isPresented: $model.channelListOpen) { ChannelListView() }
        .animation(.easeInOut(duration: 0.18), value: model.memberListVisible)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.quickSwitcherOpen.toggle() } label: {
                Label("Quick Switcher", systemImage: "command")
            }
            .help("Quick Switcher (⌘K)")
        }
        ToolbarItemGroup(placement: .principal) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle).font(.headline)
                Text(headerSubtitle).font(.caption).foregroundStyle(.tertiary)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { if model.selectedConversation?.kind == .channel { model.searchOpen.toggle() } } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find (⌘F)")
            Menu {
                if model.selectedConversation?.kind == .channel {
                    Button("Channel Modes & Bans…") { model.channelModesOpen = true }
                    Button("Channel Settings (X)…") { model.xSettingsOpen = true }
                    Divider()
                }
                Button("List Channels (/list)…") { model.requestChannelList() }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Channel Modes, Settings & List")
            Button { model.memberListVisible.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Toggle Members")
        }
    }

    private var headerTitle: String {
        guard let c = model.selectedConversation else { return "" }
        return c.kind == .server ? (model.selectedNetwork?.name ?? c.name) : c.name
    }
    private var headerSubtitle: String {
        guard let c = model.selectedConversation else { return "" }
        switch c.kind {
        case .channel: return "\(c.memberCount) members"
        case .directMessage: return "direct message"
        case .server: return model.selectedNetwork?.server ?? ""
        }
    }
}

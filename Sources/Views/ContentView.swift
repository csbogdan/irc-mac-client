import SwiftUI

/// Three-column shell: NavigationSplitView(sidebar, content, detail).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var channelModesOpen = false
    @State private var xSettingsOpen = false

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
        .sheet(isPresented: $channelModesOpen) { ChannelModesView() }
        .sheet(isPresented: $xSettingsOpen) { XChannelSettingsView() }
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
            if model.selectedConversation?.kind == .channel {
                Menu {
                    Button("Channel Modes…") { channelModesOpen = true }
                    Button("Channel Settings (X)…") { xSettingsOpen = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Channel Modes & Settings")
            }
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

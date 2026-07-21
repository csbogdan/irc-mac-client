import SwiftUI

/// Three-column shell: NavigationSplitView(sidebar, content, detail).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var channelKey = ""

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
            // Native titlebar title/subtitle — a .principal toolbar VStack gets
            // wrapped in its own glass capsule on macOS 26 and looks broken.
            .navigationTitle(headerTitle)
            .navigationSubtitle(headerSubtitle)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.quickSwitcherOpen) { QuickSwitcherView() }
        .sheet(isPresented: $model.channelModesOpen) { ChannelModesView() }
        .sheet(isPresented: $model.xSettingsOpen) { XChannelSettingsView() }
        .sheet(isPresented: $model.channelListOpen) { ChannelListView() }
        .sheet(item: $model.commandPrompt) { CommandPromptView(prompt: $0) }
        // Join refused (471/473/474/475): explain why + offer the fix.
        .alert(model.joinFailure?.title ?? "Can't join channel",
               isPresented: Binding(get: { model.joinFailure != nil },
                                    set: { if !$0 { model.joinFailure = nil } }),
               presenting: model.joinFailure) { f in
            joinFailureActions(f)
        } message: { f in
            if !f.reason.isEmpty { Text(f.reason) }
        }
        .animation(.easeInOut(duration: 0.18), value: model.memberListVisible)
    }

    @ViewBuilder private func joinFailureActions(_ f: JoinFailure) -> some View {
        switch f.code {
        case 475:
            TextField("Channel key", text: $channelKey)
            Button("Join with Key") { model.retryJoin(f, key: channelKey); channelKey = "" }
            Button("Cancel", role: .cancel) { }
        case 473:
            Button("Ask X for an Invite") { model.askXInvite(f) }
            Button("Cancel", role: .cancel) { }
        case 474:
            Button("Ask X to Unban Me") { model.askXUnban(f) }
            Button("Cancel", role: .cancel) { }
        default:
            Button("Try Again") { model.retryJoin(f) }
            Button("Cancel", role: .cancel) { }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.quickSwitcherOpen.toggle() } label: {
                Label("Quick Switcher", systemImage: "command")
            }
            .help("Quick Switcher (⌘K)")
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

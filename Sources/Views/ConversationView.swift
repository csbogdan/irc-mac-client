import SwiftUI

/// Content pane: topic bar, connection state, scrollback and composer.
struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var atBottom = true
    @State private var editingTopic = false
    @State private var topicDraft = ""

    private var conv: Conversation? { model.selectedConversation }
    private var net: Network? { model.selectedNetwork }

    var body: some View {
        VStack(spacing: 0) {
            if conv?.kind == .channel, net?.state.isLive == true { topicBar; Divider() }

            // The server console always shows its log, regardless of state.
            if conv?.kind != .server, let net, net.state.isBusy {
                connectingState(net)
            } else if conv?.kind != .server, let net, net.state == .disconnected {
                offlineState(net)
            } else {
                scrollback
                Divider()
                ComposerView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Topic bar

    private var topicBar: some View {
        HStack(spacing: 12) {
            if editingTopic {
                TextField("Channel topic", text: $topicDraft)
                    .textFieldStyle(.plain)
                    .onSubmit { commitTopic() }
                    .onExitCommand { editingTopic = false }
            } else {
                Text(conv?.topic.isEmpty == false ? conv!.topic : "Double-click for channel modes, bans & topic…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.searchOpen {
                searchField
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 40)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.channelModesOpen = true }
        .help("Double-click to open channel modes, bans & topic")
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
            TextField("Find in conversation", text: $model.searchText)
                .textFieldStyle(.plain).frame(width: 170)
            Button { model.searchOpen = false; model.searchText = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
    }

    private func startEditTopic() {
        topicDraft = conv?.topic ?? ""; editingTopic = true
    }
    private func commitTopic() {
        if let id = conv?.id { model.setTopic(topicDraft, for: id) }
        editingTopic = false
    }

    // MARK: Scrollback

    private var scrollback: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(rows) { row in
                    MessageRowView(row: row)
                        .id(row.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                // Visibility of this anchor tells us whether the user is parked
                // at the bottom — follow only happens then.
                Color.clear.frame(height: 1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .id("BOTTOM")
                    .onAppear { atBottom = true }
                    .onDisappear { atBottom = false }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if conv?.kind == .channel { model.channelModesOpen = true }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button { atBottom = true; withAnimation { proxy.scrollTo("BOTTOM") } } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent).tint(.gray)
                    .padding(.trailing, 18).padding(.bottom, 14)
                }
            }
            .onChange(of: conv?.messages.count) { _, _ in
                // Only follow new messages if you're already at the bottom.
                if atBottom { withAnimation { proxy.scrollTo("BOTTOM") } }
            }
            .onChange(of: model.selectedID) { _, _ in
                atBottom = true
                proxy.scrollTo("BOTTOM")
            }
        }
    }

    private var rows: [MessageRow] {
        guard let conv else { return [] }
        return MessageGrouper.rows(for: conv, selfNick: model.selfNick, keywords: model.highlightKeywords,
                                   searchQuery: model.searchOpen ? model.searchText : nil)
    }

    // MARK: Connection states

    private func connectingState(_ net: Network) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Connecting to \(net.name)…").font(.headline)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.connectingLog, id: \.self) { line in
                    Text(line).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func offlineState(_ net: Network) -> some View {
        VStack(spacing: 14) {
            Circle().fill(.tertiary).frame(width: 9, height: 9)
            Text("\(net.name) is disconnected").font(.headline)
            Button("Connect") { model.connect(net.id) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

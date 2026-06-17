import SwiftUI

struct MessageListView: View {
    @Bindable var channel: ChannelModel
    @State private var searchText = ""
    @State private var atBottom = true

    private var visibleLines: [ChatLine] {
        guard !searchText.isEmpty else { return channel.lines }
        return channel.lines.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
            || $0.sender.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleLines) { line in
                        MessageRowView(line: line)
                            .id(line.id)
                            .padding(.horizontal, 12)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.vertical, 8)
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button {
                        withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .onChange(of: channel.lines.count) { _, _ in
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: channel.id) { _, _ in
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find in \(channel.name)")
    }

    private let bottomAnchor = "bottom-anchor"
}

import SwiftUI

/// ⌘K quick switcher — fuzzy jump to any channel or DM across networks.
struct QuickSwitcherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var results: [(conv: Conversation, network: Network)] {
        let all = model.flatConversations
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { "\($0.conv.name) \($0.network.name)".lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Text("⌘K").foregroundStyle(.tertiary)
                TextField("Jump to a channel or person…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.return) { choose(); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                    .onChange(of: query) { _, _ in index = 0 }
            }
            .padding(13)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.conv.id) { i, item in
                        row(item.conv, item.network, selected: i == index)
                            .onTapGesture { model.select(item.conv.id); dismiss() }
                    }
                    if results.isEmpty {
                        Text("No matches").foregroundStyle(.tertiary).padding(20)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear { focused = true }
    }

    private func row(_ conv: Conversation, _ net: Network, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Group {
                if conv.kind == .directMessage {
                    Circle().fill(NickColor.color(for: conv.name, dark: scheme == .dark))
                        .overlay(Text(NickColor.monogram(conv.name)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.mention)
                        .overlay(Text("#").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                }
            }
            .frame(width: 22, height: 22)
            Text(conv.name).font(.system(size: 13.5, weight: .medium))
            Spacer()
            Text(net.name).font(.system(size: 11)).foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? AnyShapeStyle(Theme.mention) : AnyShapeStyle(.clear)))
        .foregroundStyle(selected ? .white : .primary)
        .contentShape(Rectangle())
    }

    private func move(_ d: Int) -> KeyPress.Result {
        let n = results.count
        guard n > 0 else { return .ignored }
        index = max(0, min(index + d, n - 1))
        return .handled
    }
    private func choose() {
        guard index < results.count else { return }
        model.select(results[index].conv.id); dismiss()
    }
}

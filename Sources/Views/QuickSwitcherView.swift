import SwiftUI

/// ⌘K fuzzy channel/DM switcher presented as a sheet.
struct QuickSwitcherView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [(network: NetworkModel, channel: ChannelModel)] {
        let all = app.allBuffers
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.channel.name.localizedCaseInsensitiveContains(query)
            || $0.network.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to channel or person…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { activateFirst() }
            }
            .padding(12)
            Divider()

            List(results, id: \.channel.id) { item in
                Button {
                    app.select(item.channel)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: item.channel.symbolName).foregroundStyle(.secondary)
                        Text(item.channel.name)
                        Spacer()
                        Text(item.network.name).foregroundStyle(.secondary).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 460, height: 360)
        .background(.regularMaterial)
    }

    private func activateFirst() {
        if let first = results.first {
            app.select(first.channel)
            dismiss()
        }
    }
}

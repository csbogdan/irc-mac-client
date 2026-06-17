import SwiftUI

/// Browsable results of /list — filter and double-click (or Join) to join.
struct ChannelListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [ChannelListItem] {
        let items = model.channelList.sorted { $0.users > $1.users }
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.name.lowercased().contains(q) || $0.topic.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Channels — \(model.channelList.count)").font(.headline)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter name or topic", text: $query)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()

            Table(results) {
                TableColumn("Channel") { item in
                    Text(item.name).fontWeight(.medium)
                        .onTapGesture(count: 2) { model.joinChannel(item.name); dismiss() }
                }
                TableColumn("Users") { item in Text("\(item.users)").monospacedDigit() }
                    .width(min: 50, ideal: 60, max: 80)
                TableColumn("Topic") { item in
                    Text(item.topic).foregroundStyle(.secondary).lineLimit(1)
                }
                TableColumn("") { item in
                    Button("Join") { model.joinChannel(item.name); dismiss() }
                }
                .width(60)
            }
        }
        .frame(width: 760, height: 580)
    }
}

import SwiftUI

/// Settings scene — native TabView style with the standard sections.
struct SettingsView: View {
    @Binding var appearance: String

    var body: some View {
        TabView {
            AccountsSettings().tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            AppearanceSettings(appearance: $appearance).tabItem { Label("Appearance", systemImage: "paintpalette") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct AccountsSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            ForEach(model.networks) { net in
                LabeledContent(net.name) {
                    HStack {
                        Text(net.server).foregroundStyle(.secondary)
                        Circle().fill(net.state.dotColor).frame(width: 7, height: 7)
                    }
                }
            }
            Button("Add Network…") { }
        }
        .formStyle(.grouped).padding()
    }
}

private struct AppearanceSettings: View {
    @Binding var appearance: String
    @AppStorage("accent") private var accent = Theme.Accent.graphite.rawValue
    @AppStorage("density") private var density = Theme.Density.comfortable.rawValue
    @AppStorage("showTimestamps") private var showTimestamps = true

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
            Picker("Accent", selection: $accent) {
                ForEach(Theme.Accent.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
            Picker("Density", selection: $density) {
                ForEach(Theme.Density.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
            Toggle("Show timestamps", isOn: $showTimestamps)
        }
        .formStyle(.grouped).padding()
    }
}

private struct NotificationsSettings: View {
    @AppStorage("notifyMentions") private var notifyMentions = true
    @AppStorage("notifyDMs") private var notifyDMs = true
    @AppStorage("dockBadge") private var dockBadge = true
    var body: some View {
        Form {
            Toggle("Notify on mentions", isOn: $notifyMentions)
            Toggle("Notify on direct messages", isOn: $notifyDMs)
            Toggle("Show unread count on Dock icon", isOn: $dockBadge)
        }
        .formStyle(.grouped).padding()
    }
}

private struct AdvancedSettings: View {
    @AppStorage("autoReconnect") private var autoReconnect = true
    var body: some View {
        Form {
            Toggle("Reconnect automatically", isOn: $autoReconnect)
            LabeledContent("Transport", value: "Mock service (offline demo)")
            Text("Swap to the live NWConnection client in AppModel.client.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding()
    }
}

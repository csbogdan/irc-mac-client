import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            NotificationsSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }
            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct AccountsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Networks") {
                ForEach(app.networks) { network in
                    LabeledContent(network.name) {
                        Text("\(network.config.host):\(String(network.config.port))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage("showTimestamps") private var showTimestamps = true
    @AppStorage("compactJoinPart") private var compactJoinPart = true
    @AppStorage("useMonospace") private var useMonospace = false

    var body: some View {
        Form {
            Toggle("Show timestamps", isOn: $showTimestamps)
            Toggle("Collapse join/part noise", isOn: $compactJoinPart)
            Toggle("Monospaced message font", isOn: $useMonospace)
        }
        .formStyle(.grouped)
    }
}

private struct NotificationsSettings: View {
    @AppStorage("notifyMentions") private var notifyMentions = true
    @AppStorage("notifyDMs") private var notifyDMs = true
    @AppStorage("bounceDock") private var bounceDock = false

    var body: some View {
        Form {
            Toggle("Notify on mentions", isOn: $notifyMentions)
            Toggle("Notify on direct messages", isOn: $notifyDMs)
            Toggle("Bounce Dock icon", isOn: $bounceDock)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @AppStorage("reconnectOnDrop") private var reconnectOnDrop = true
    @AppStorage("logRawProtocol") private var logRawProtocol = false

    var body: some View {
        Form {
            Toggle("Auto-reconnect on disconnect", isOn: $reconnectOnDrop)
            Toggle("Log raw IRC protocol", isOn: $logRawProtocol)
        }
        .formStyle(.grouped)
    }
}

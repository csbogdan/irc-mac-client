import SwiftUI

/// Menu-bar commands with real macOS shortcuts.
struct AppCommands: Commands {
    @Bindable var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") {
                app.add(ServerConfig(name: "New Network", host: "irc.example.net", nick: "bogdan"))
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Quick Switch Channel…") {
                app.quickSwitcherPresented = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            ForEach(1...9, id: \.self) { index in
                Button("Channel \(index)") {
                    app.selectChannelByIndex(index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }
        }
    }
}

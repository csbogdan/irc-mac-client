import SwiftUI

@main
struct RelayApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { RelayCommands(model: model, appearance: $appearance) }

        Settings {
            SettingsView(appearance: $appearance)
                .environment(model)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

// MARK: - Menu bar

struct RelayCommands: Commands {
    @Bindable var model: AppModel
    @Binding var appearance: String

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") { model.quickSwitcherOpen = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Navigate") {
            Button("Quick Switcher…") { model.quickSwitcherOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Find in Conversation…") {
                if model.selectedConversation?.kind == .channel { model.searchOpen = true }
            }
            .keyboardShortcut("f", modifiers: .command)
            Divider()
            ForEach(1...9, id: \.self) { i in
                Button("Jump to Conversation \(i)") { model.selectIndex(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
            }
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Members") { model.memberListVisible.toggle() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        }
    }
}

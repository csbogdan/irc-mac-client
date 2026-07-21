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

        Window("About Relay", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Relay Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 860, height: 640)
        .defaultPosition(.center)
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Relay") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") { model.quickSwitcherOpen = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Private Session") {
                if let id = model.selectedNetwork?.id { model.startPrivateSession(id) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Relay Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
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

// MARK: - About

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    /// Days since mIRC 1.0 shipped (28 Feb 1995) — still well within the trial.
    private var trialDay: Int {
        let mirc = DateComponents(calendar: .current, year: 1995, month: 2, day: 28).date ?? .now
        return max(1, Calendar.current.dateComponents([.day], from: mirc, to: .now).day ?? 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 84, height: 84)
            Text("Relay").font(.system(size: 26, weight: .bold, design: .rounded))
            Text(version).font(.system(size: 12)).foregroundStyle(.secondary)

            VStack(spacing: 7) {
                Text("Made by Rufus").font(.system(size: 13, weight: .semibold))
                Text("100% vibe-coded: not a single line typed by hand.\nThe code has never been read — only felt.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

            Divider().padding(.vertical, 4)

            VStack(spacing: 5) {
                Text("An homage to mIRC.")
                    .font(.system(size: 11.5, weight: .medium))
                Text("Day \(trialDay.formatted()) of your 30-day evaluation period.\nPlease consider registering.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("🐟 *slaps you around a bit with a large trout*")
                    .font(.system(size: 11)).italic().foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}

import SwiftUI

@main
struct IRCClientApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    app.bootstrap()
                    app.notifications.requestAuthorization()
                }
        }
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

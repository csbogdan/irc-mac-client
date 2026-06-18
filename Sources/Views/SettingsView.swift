import SwiftUI

/// Settings scene — native TabView style with the standard sections.
struct SettingsView: View {
    @Binding var appearance: String

    var body: some View {
        TabView {
            ConnectionsSettings().tabItem { Label("Connections", systemImage: "network") }
            ArtSettings().tabItem { Label("ASCII Art", systemImage: "paintbrush.pointed") }
            AppearanceSettings(appearance: $appearance).tabItem { Label("Appearance", systemImage: "paintpalette") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 720, height: 540)
    }
}

// MARK: - Connections (server configuration)

private struct ConnectionsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        @Bindable var model = model

        HSplitView {
            // Master list of servers
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.serverConfigs) { cfg in
                        serverRow(cfg).tag(cfg.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 0) {
                    Button { selection = model.addServer().id } label: {
                        Image(systemName: "plus").frame(width: 24, height: 22)
                    }
                    Button { deleteSelected() } label: {
                        Image(systemName: "minus").frame(width: 24, height: 22)
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6).padding(.vertical, 3)
            }
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 260)

            // Detail editor
            Group {
                if let id = selection, let i = model.serverConfigs.firstIndex(where: { $0.id == id }) {
                    ServerEditor(initial: model.serverConfigs[i],
                                 state: model.state(of: id) ?? .disconnected,
                                 onSave: { model.updateServer($0) },
                                 onConnect: { model.connect(id) },
                                 onDisconnect: { model.disconnect(id) })
                    .id(id)
                } else {
                    ContentUnavailableView("No Server Selected", systemImage: "network",
                                           description: Text("Select a server to edit, or add one."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = model.serverConfigs.first?.id } }
    }

    private func serverRow(_ cfg: ServerConfig) -> some View {
        HStack(spacing: 8) {
            Circle().fill((model.state(of: cfg.id) ?? .disconnected).dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(cfg.name).font(.system(size: 13, weight: .medium))
                Text("\(cfg.host):\(String(cfg.port))").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        let next = model.serverConfigs.first { $0.id != id }?.id
        model.deleteServer(id)
        selection = next
    }
}

private extension AppModel {
    func state(of id: String) -> ConnectionState? { networks.first { $0.id == id }?.state }
}

// MARK: - Single-server editor

private struct ServerEditor: View {
    let state: ConnectionState
    let onSave: (ServerConfig) -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    // Local editable draft — decoupled from the @Observable model so typing
    // never re-renders the model mid-keystroke (which stole focus before).
    @State private var config: ServerConfig
    @State private var newChannel = ""

    init(initial: ServerConfig, state: ConnectionState,
         onSave: @escaping (ServerConfig) -> Void,
         onConnect: @escaping () -> Void, onDisconnect: @escaping () -> Void) {
        self.state = state
        self.onSave = onSave
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        _config = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(state.dotColor).frame(width: 8, height: 8)
                        Text(statusLabel).foregroundStyle(.secondary)
                        Spacer()
                        if state.isLive || state.isBusy {
                            Button("Disconnect", action: onDisconnect)
                        } else {
                            Button("Connect", action: onConnect)
                        }
                    }
                }
            }

            Section("Server") {
                TextField("Name", text: $config.name)
                TextField("Host", text: $config.host)
                TextField("Port", value: $config.port, format: .number.grouping(.never))
                Toggle("Use TLS / SSL", isOn: $config.useTLS)
            }

            Section("Identity") {
                TextField("Nickname", text: $config.nick)
                TextField("Alternate nickname", text: $config.altNick)
                TextField("Username", text: $config.username, prompt: Text(config.nick.isEmpty ? "same as nickname" : config.nick))
                TextField("Real name", text: $config.realName)
                SecureField("Server password", text: $config.serverPassword)
            }

            Section("Authentication") {
                Toggle("Authenticate with SASL", isOn: $config.saslEnabled)
                if config.saslEnabled {
                    TextField("Account", text: $config.saslAccount)
                    SecureField("Password", text: $config.saslPassword)
                }
            }

            Section {
                ForEach(Undernet.userModes) { mode in
                    Toggle(isOn: Binding(
                        get: { config.userModes.contains(mode.letter) },
                        set: { on in
                            if on { config.userModes.insert(mode.letter) }
                            else { config.userModes.remove(mode.letter) }
                        })
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("+\(mode.letter)  ·  \(mode.name)")
                            Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("User Modes (set on connect)")
            }

            Section {
                ForEach($config.onConnectCommands) { $cmd in
                    HStack(spacing: 8) {
                        TextField("Command", text: $cmd.line,
                                  prompt: Text("/msg NickServ identify …  or  MODE %nick% +x"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        HStack(spacing: 2) {
                            TextField("Delay", value: $cmd.delay, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 44).multilineTextAlignment(.trailing)
                            Text("s").foregroundStyle(.secondary)
                        }
                        Button { remove(cmd) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .onMove { config.onConnectCommands.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    config.onConnectCommands.append(PerformCommand())
                } label: { Label("Add command", systemImage: "plus") }

                LabeledContent("Delay before joining channels") {
                    HStack(spacing: 2) {
                        TextField("0", value: $config.joinDelay, format: .number)
                            .frame(width: 44).multilineTextAlignment(.trailing)
                        Text("s").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("On Connect")
            } footer: {
                Text("Commands run in order, each after its delay. The whole list finishes before any channels are joined. Use %nick% for your current nick.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Auto-join Channels") {
                ForEach(config.autoJoinChannels, id: \.self) { chan in
                    HStack {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        Text(chan)
                        Spacer()
                        Button { config.autoJoinChannels.removeAll { $0 == chan } } label: {
                            Image(systemName: "minus.circle.fill")
                        }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Channel", text: $newChannel, prompt: Text("#channel"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addChannel)
                    Button("Add", action: addChannel).disabled(newChannel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Toggle("Connect on launch", isOn: $config.connectOnLaunch)
                Toggle("Reconnect automatically", isOn: $config.autoReconnect)
            } header: {
                Text("Options")
            } footer: {
                Text("Connects to \(config.host):\(String(config.port)) over a real \(config.useTLS ? "TLS" : "TCP") socket.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: config) { _, new in onSave(new) }
    }

    private var statusLabel: String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .registering: return "Registering…"
        case .disconnected: return "Offline"
        }
    }

    private func addChannel() {
        let raw = newChannel.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let chan = raw.hasPrefix("#") || raw.hasPrefix("&") ? raw : "#\(raw)"
        if !config.autoJoinChannels.contains(chan) { config.autoJoinChannels.append(chan) }
        newChannel = ""
    }

    private func remove(_ cmd: PerformCommand) {
        config.onConnectCommands.removeAll { $0.id == cmd.id }
    }
}

// MARK: - ASCII Art editor

private struct ArtSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Form {
                Section {
                    if model.customArt.isEmpty {
                        Text("No custom art yet. Add a line below — use %nick% to address whoever you right-click, and mIRC color codes (\\u{3}4 = red) for color.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach($model.customArt) { $art in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Name", text: $art.name)
                                    .textFieldStyle(.roundedBorder).frame(width: 160)
                                Spacer()
                                Button { model.deleteCustomArt(art.id) } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless).foregroundStyle(.red)
                            }
                            TextField("Template (e.g. \\u{3}4♥ %nick% ♥)", text: $art.template)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text(RichText.render(ArtCatalog.render(art.template, nick: model.selfNick),
                                                 selfNick: "", dark: true))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.85)))
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("My ASCII Art")
                }
            }
            .formStyle(.grouped)
            .onChange(of: model.customArt) { _, _ in model.saveCustomArt() }

            Divider()
            HStack {
                Button { model.addCustomArt() } label: { Label("Add Line", systemImage: "plus") }
                Spacer()
                Text("Reachable from the composer 🎨 and nick right-click menus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

// MARK: - Other tabs

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
    var body: some View {
        Form {
            LabeledContent("Transport", value: "Mock service (offline demo)")
            Text("Swap to the live NWConnection client in AppModel.client. Per-server connection details, SASL, on-connect commands and auto-join are configured in the Connections tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding()
    }
}

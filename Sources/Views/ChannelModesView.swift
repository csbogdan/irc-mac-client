import SwiftUI

/// Editor for Undernet channel modes on the selected channel. Toggling a mode
/// sends the MODE line immediately and tracks it optimistically.
struct ChannelModesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var conv: Conversation? { model.selectedConversation }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let conv, conv.kind == .channel {
                Form {
                    Section("Flags") {
                        ForEach(Undernet.editableChannelModes.filter { $0.param == .none }) { mode in
                            Toggle(isOn: binding(for: mode, in: conv)) {
                                row(mode)
                            }
                        }
                    }
                    Section("Limit & Key") {
                        limitRow(conv)
                        keyRow(conv)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Not a Channel", systemImage: "number",
                                       description: Text("Select a channel to edit its modes."))
            }
        }
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack {
            Text("Channel Modes — \(conv?.name ?? "")").font(.headline)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func row(_ mode: ChannelMode) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("+\(mode.letter)  ·  \(mode.name)")
            Text(mode.detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(for mode: ChannelMode, in conv: Conversation) -> Binding<Bool> {
        Binding(
            get: { conv.activeModes.contains(mode.letter) },
            set: { model.setChannelMode(mode.letter, enabled: $0, for: conv.id) }
        )
    }

    @State private var limitText = ""
    private func limitRow(_ conv: Conversation) -> some View {
        HStack {
            Text("+l  ·  User limit")
            Spacer()
            TextField("none", text: $limitText)
                .frame(width: 70).multilineTextAlignment(.trailing)
                .onAppear { limitText = conv.modeLimit.map(String.init) ?? "" }
            Button("Set") {
                if let n = Int(limitText), n > 0 { model.setChannelMode("l", enabled: true, param: String(n), for: conv.id) }
            }
            Button("Clear") { model.setChannelMode("l", enabled: false, for: conv.id); limitText = "" }
                .disabled(conv.modeLimit == nil)
        }
    }

    @State private var keyText = ""
    private func keyRow(_ conv: Conversation) -> some View {
        HStack {
            Text("+k  ·  Key")
            Spacer()
            TextField("none", text: $keyText)
                .frame(width: 110)
                .onAppear { keyText = conv.modeKey ?? "" }
            Button("Set") {
                if !keyText.isEmpty { model.setChannelMode("k", enabled: true, param: keyText, for: conv.id) }
            }
            Button("Clear") {
                model.setChannelMode("k", enabled: false, param: conv.modeKey, for: conv.id); keyText = ""
            }.disabled(conv.modeKey == nil)
        }
    }
}

/// Editor for X (Channel Service) channel settings — `/msg X SET #chan …`.
struct XChannelSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var toggles: [String: Bool] = [:]
    @State private var numbers: [String: Double] = [:]
    @State private var texts: [String: String] = [:]

    private var conv: Conversation? { model.selectedConversation }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Channel Settings (X) — \(conv?.name ?? "")").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()

            if let conv, conv.kind == .channel {
                Form {
                    Section {
                        Text("Each control sends `/msg X SET \(conv.name) <OPTION> <value>`.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Undernet.xChannelSettings) { setting in
                        settingRow(setting, convID: conv.id)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Not a Channel", systemImage: "number")
            }
        }
        .frame(width: 520, height: 600)
    }

    @ViewBuilder
    private func settingRow(_ setting: XChannelSetting, convID: String) -> some View {
        switch setting.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { toggles[setting.option] ?? false },
                set: { v in toggles[setting.option] = v
                    model.sendXChannelSet(setting.option, value: v ? "ON" : "OFF", for: convID) })
            ) { label(setting.option, setting.detail) }

        case let .number(range):
            HStack {
                label(setting.option, setting.detail)
                Spacer()
                TextField("", value: Binding(
                    get: { numbers[setting.option] ?? Double(range.lowerBound) },
                    set: { numbers[setting.option] = $0 }), format: .number)
                    .frame(width: 64).multilineTextAlignment(.trailing)
                Stepper("", value: Binding(
                    get: { numbers[setting.option] ?? Double(range.lowerBound) },
                    set: { numbers[setting.option] = $0 }),
                    in: Double(range.lowerBound)...Double(range.upperBound)).labelsHidden()
                Button("Set") {
                    let v = Int(numbers[setting.option] ?? Double(range.lowerBound))
                    model.sendXChannelSet(setting.option, value: String(v), for: convID)
                }
            }

        case let .text(maxLen):
            HStack(alignment: .firstTextBaseline) {
                label(setting.option, setting.detail)
                Spacer()
                TextField("value", text: Binding(
                    get: { texts[setting.option] ?? "" },
                    set: { texts[setting.option] = String($0.prefix(maxLen)) }))
                    .frame(width: 200)
                Button("Set") {
                    model.sendXChannelSet(setting.option, value: texts[setting.option] ?? "", for: convID)
                }
            }
        }
    }

    private func label(_ option: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(option).font(.system(size: 12.5, weight: .medium, design: .monospaced))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

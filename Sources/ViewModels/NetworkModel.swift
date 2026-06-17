import Foundation
import Observation

@MainActor
@Observable
final class NetworkModel: Identifiable {
    let id = UUID()
    var config: ServerConfig
    var nick: String
    var state: ConnectionState = .disconnected
    var channels: [ChannelModel] = []

    @ObservationIgnored private var connection: (any IRCConnection)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored weak var app: AppModel?

    var name: String { config.name }

    init(config: ServerConfig) {
        self.config = config
        self.nick = config.nick
        // The network's own status buffer.
        channels.append(ChannelModel(name: config.name, kind: .server))
    }

    func connect() {
        guard connection == nil else { return }
        let conn = IRCConnectionFactory.make(config: config)
        connection = conn
        pump = Task { [weak self] in
            for await event in conn.events {
                self?.apply(event)
            }
        }
        Task { await conn.start() }
    }

    func disconnect() {
        let conn = connection
        connection = nil
        pump?.cancel()
        pump = nil
        Task { await conn?.stop() }
    }

    func send(_ raw: String) {
        Task { await connection?.send(line: raw) }
    }

    // MARK: - Buffers

    func channel(named name: String, kind: ChannelModel.Kind) -> ChannelModel {
        if let existing = channels.first(where: { $0.name.caseInsensitiveEquals(name) }) {
            return existing
        }
        let model = ChannelModel(name: name, kind: kind)
        channels.append(model)
        return model
    }

    private var statusBuffer: ChannelModel { channels[0] }

    // MARK: - Event handling

    private func apply(_ event: IRCEvent) {
        switch event {
        case .stateChanged(let s):
            state = s
            statusBuffer.append(ChatLine(kind: .server, sender: "*", text: s.label), isActive: isActive(statusBuffer))

        case .channelJoined(let name, let topic):
            let ch = channel(named: name, kind: .channel)
            if !topic.isEmpty { ch.topic = topic }

        case .channelParted(let name):
            channels.removeAll { $0.name.caseInsensitiveEquals(name) && $0.kind == .channel }

        case .line(let name, let line):
            let ch = channel(named: name, kind: .channel)
            ch.append(line, isActive: isActive(ch))

        case .privateMessage(let peer, let line):
            let ch = channel(named: peer, kind: .dm)
            ch.append(line, isActive: isActive(ch))

        case .members(let name, let members):
            channel(named: name, kind: .channel).members = members

        case .topic(let name, let topic):
            channel(named: name, kind: .channel).topic = topic

        case .error(let message):
            statusBuffer.append(ChatLine(kind: .server, sender: "!", text: message), isActive: isActive(statusBuffer))
        }
    }

    private func isActive(_ channel: ChannelModel) -> Bool {
        app?.selection == channel.id
    }
}

extension String {
    func caseInsensitiveEquals(_ other: String) -> Bool {
        caseInsensitiveCompare(other) == .orderedSame
    }
}

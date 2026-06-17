import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var networks: [NetworkModel] = []
    var selection: UUID?
    var memberListVisible = true
    var quickSwitcherPresented = false

    @ObservationIgnored let notifications = NotificationService()

    var selectedChannel: ChannelModel? {
        guard let selection else { return nil }
        for network in networks {
            if let channel = network.channels.first(where: { $0.id == selection }) {
                return channel
            }
        }
        return nil
    }

    var selectedNetwork: NetworkModel? {
        guard let selection else { return nil }
        return networks.first { $0.channels.contains { $0.id == selection } }
    }

    /// Flat list of every channel/DM for the quick-switcher.
    var allBuffers: [(network: NetworkModel, channel: ChannelModel)] {
        networks.flatMap { network in network.channels.map { (network, $0) } }
    }

    var totalUnread: Int {
        networks.reduce(0) { $0 + $1.channels.reduce(0) { $0 + $1.unread } }
    }

    func bootstrap() {
        guard networks.isEmpty else { return }
        let seeds = [
            ServerConfig(name: "Libera.Chat", host: "irc.libera.chat", nick: "bogdan",
                         autoJoin: ["#swift", "#macdev"]),
            ServerConfig(name: "OFTC", host: "irc.oftc.net", nick: "bogdan",
                         autoJoin: ["#debian"]),
        ]
        seeds.forEach { add($0) }
        selection = networks.first?.channels.first(where: { $0.kind == .channel })?.id
            ?? networks.first?.channels.first?.id
    }

    @discardableResult
    func add(_ config: ServerConfig) -> NetworkModel {
        let model = NetworkModel(config: config)
        model.app = self
        networks.append(model)
        model.connect()
        return model
    }

    func select(_ channel: ChannelModel) {
        selection = channel.id
        channel.markRead()
    }

    func selectChannelByIndex(_ index: Int) {
        let channels = networks.flatMap(\.channels)
        guard channels.indices.contains(index) else { return }
        select(channels[index])
    }
}

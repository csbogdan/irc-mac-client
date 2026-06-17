import Foundation
import UserNotifications
import AppKit

/// Thin wrapper over UNUserNotificationCenter + the Dock badge for mentions/DMs.
@MainActor
final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyMention(network: String, channel: String, sender: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(sender) in \(channel)"
        content.subtitle = network
        content.body = text
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func updateDockBadge(unread: Int) {
        NSApplication.shared.dockTile.badgeLabel = unread > 0 ? String(unread) : nil
    }
}

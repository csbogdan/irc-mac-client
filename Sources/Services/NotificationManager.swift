import AppKit
import UserNotifications

/// Bridge to Notification Center: posts mention/DM notifications and routes
/// clicks back into the app. Banners are suppressed while the app is frontmost
/// — notifications exist for the background.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    /// Called (on the main actor) with the conversation ID when the user
    /// clicks a notification.
    var onSelect: ((String) -> Void)?
    private var authorized = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in self.authorized = ok }
        }
    }

    func post(convID: String, title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = convID   // one stack per conversation
        content.userInfo = ["convID": convID]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Suppress the banner while the app is active — in-app badges cover that.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let active = await MainActor.run { NSApp.isActive }
        return active ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let convID = response.notification.request.content.userInfo["convID"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let convID { self.onSelect?(convID) }
        }
    }
}

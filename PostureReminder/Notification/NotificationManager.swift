import UserNotifications
import Foundation

final class NotificationManager {

    private var lastSentAt: Date?
    private let cooldown: TimeInterval = 10 * 60

    // MARK: - Authorization

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error = error {
                print("[PostureReminder] Notification auth error: \(error)")
            }
            if !granted {
                print("[PostureReminder] Notification permission denied. " +
                      "Open System Settings → Notifications → PostureReminder")
            }
        }
    }

    // MARK: - Send reminder

    func sendSittingReminderIfNeeded(duration: TimeInterval) {
        let now = Date()
        if let last = lastSentAt, now.timeIntervalSince(last) < cooldown { return }
        lastSentAt = now

        let minutes = Int(duration / 60)
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.title", comment: "")
        content.body  = String(
            format: NSLocalizedString("notification.body", comment: ""),
            minutes
        )
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        deliver(content, id: "sitting-\(Int(now.timeIntervalSince1970))")
    }

    // MARK: - Test

    /// Bypasses cooldown and sitting threshold — useful for verifying
    /// notification permission is granted and the system actually delivers banners.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "PostureReminder — Test"
        content.body  = "Notifications are working correctly."
        content.sound = .default
        deliver(content, id: "test-\(Date().timeIntervalSince1970)")
    }

    // MARK: - Reset

    func resetCooldown() {
        lastSentAt = nil
    }

    // MARK: - Private

    private func deliver(_ content: UNMutableNotificationContent, id: String) {
        checkAuthorizationAndSend {
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[PostureReminder] Failed to deliver notification '\(id)': \(error)")
                }
            }
        }
    }

    private func checkAuthorizationAndSend(_ block: @escaping () -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                block()
            case .notDetermined:
                // Re-request then try again
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound]
                ) { granted, _ in
                    if granted { block() }
                }
            default:
                print("[PostureReminder] Notifications not authorized " +
                      "(status=\(settings.authorizationStatus.rawValue)). " +
                      "Enable in System Settings → Notifications → PostureReminder.")
            }
        }
    }
}

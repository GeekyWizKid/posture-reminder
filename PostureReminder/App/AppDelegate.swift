import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let stateManager = StateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        menuBarController = MenuBarController(stateManager: stateManager)
        stateManager.start()

        checkNotificationPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateManager.stop()
    }

    // MARK: - Notification permission onboarding

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    // First launch — show the system permission dialog
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound]
                    ) { granted, _ in
                        if !granted {
                            DispatchQueue.main.async { self?.showPermissionDeniedAlert() }
                        }
                    }
                case .denied:
                    // User previously denied — guide them to Settings
                    self?.showPermissionDeniedAlert()
                default:
                    break
                }
            }
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("onboard.title", comment: "")
        alert.informativeText = NSLocalizedString("onboard.body", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("onboard.open_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("onboard.later", comment: ""))

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            // Deep-link directly to the Notifications pane
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// Show banners even while the app is "foreground" (status-bar only)
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

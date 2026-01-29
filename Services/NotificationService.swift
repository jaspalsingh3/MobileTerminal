//
//  NotificationService.swift
//  Mobile Terminal
//
//  Local notifications for terminal command completion
//

import SwiftUI
import UserNotifications

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var pendingCommandId: String?

    private let notificationCenter = UNUserNotificationCenter.current()

    // Patterns that indicate command completion (prompt returned)
    private let completionPatterns = [
        "\\$\\s*$",           // Bash prompt ending with $
        "❯\\s*$",            // Zsh prompt
        ">>>\\s*$",          // Python prompt
        "\\]\\$\\s*$",       // Bash with path ending
        "%\\s*$",            // Zsh ending with %
    ]

    private override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        notificationCenter.getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    /// Start monitoring for command completion
    func startMonitoring(commandId: String) {
        pendingCommandId = commandId
    }

    /// Stop monitoring
    func stopMonitoring() {
        pendingCommandId = nil
    }

    /// Check if terminal output indicates command completion
    func checkForCompletion(output: String) -> Bool {
        for pattern in completionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)) != nil {
                return true
            }
        }
        return false
    }

    /// Send notification that command completed
    func notifyCommandCompleted(command: String? = nil) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Terminal"
        content.body = command != nil ? "Command completed: \(command!)" : "Command completed"
        content.sound = .default
        content.categoryIdentifier = "TERMINAL_COMMAND"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }

        pendingCommandId = nil
        HapticManager.shared.success()
    }

    /// Send notification for errors
    func notifyError(message: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Terminal Error"
        content.body = message
        content.sound = .defaultCritical
        content.categoryIdentifier = "TERMINAL_ERROR"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
        HapticManager.shared.error()
    }

    /// Schedule a reminder notification
    func scheduleReminder(message: String, after seconds: TimeInterval) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Terminal Reminder"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "terminal_reminder_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    /// Clear all pending notifications
    func clearAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// Setup notification categories and actions
    func setupNotificationCategories() {
        // Action to open terminal
        let openAction = UNNotificationAction(
            identifier: "OPEN_TERMINAL",
            title: "Open Terminal",
            options: [.foreground]
        )

        // Action to dismiss
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )

        // Category for command completion
        let commandCategory = UNNotificationCategory(
            identifier: "TERMINAL_COMMAND",
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Category for errors
        let errorCategory = UNNotificationCategory(
            identifier: "TERMINAL_ERROR",
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([commandCategory, errorCategory])
    }
}

// MARK: - App Delegate Extension for Notification Handling

#if os(iOS)
extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "OPEN_TERMINAL":
            // Post notification to open terminal tab
            NotificationCenter.default.post(name: .openTerminalTab, object: nil)
        default:
            break
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openTerminalTab = Notification.Name("openTerminalTab")
}
#endif

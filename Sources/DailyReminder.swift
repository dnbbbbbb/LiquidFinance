import Foundation
import UserNotifications

enum DailyReminder {
    static let identifier = "liquidfinance.daily-entry-reminder"

    static func configure(enabled: Bool, hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return true }

        var settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            settings = await center.notificationSettings()
            allowed = allowed && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
        guard allowed else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Ghi lại chi tiêu hôm nay"
        content.body = "Dành một phút để cập nhật tài chính của bạn."
        content.sound = .default
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do { try await center.add(request); return true }
        catch { return false }
    }
}

enum BudgetAlertNotification {
    static func configure(enabled: Bool) async -> Bool {
        guard enabled else { return true }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { return true }
        guard settings.authorizationStatus == .notDetermined else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func send(identifier: String, title: String, body: String) async {
        guard await configure(enabled: true) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }
}

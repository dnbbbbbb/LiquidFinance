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

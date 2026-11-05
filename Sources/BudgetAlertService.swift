import Foundation
import UserNotifications

enum BudgetAlertService {
    private static let notificationPrefix = "liquidfinance.budget-alert"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    @MainActor static func evaluate(budgets: [SpendingBudget], store: FinanceStore, date: Date) async {
        guard budgets.contains(where: { $0.alertsEnabled && $0.monthlyLimit > 0 }) else { return }
        guard await requestAuthorization() else { return }
        for budget in budgets where budget.alertsEnabled && budget.monthlyLimit > 0 {
            let range = budget.period.range(containing: date)
            let spent = store.spent(for: budget, from: range.0, through: range.1)
            let percentage = spent / budget.monthlyLimit * 100
            let milestone: String?
            let body: String
            if percentage > 100 {
                milestone = "over"
                let overage = MoneyText.string(spent - budget.monthlyLimit, currencyCode: store.preferences.currencyCode)
                body = "Bạn đã vượt ngân sách \(overage) cho \(budget.category.name)."
            } else if percentage >= 100 {
                milestone = "limit"
                body = "Bạn đã chạm giới hạn ngân sách cho \(budget.category.name)."
            } else if percentage >= Double(budget.alertThreshold) {
                milestone = "warning"
                body = "Bạn đã dùng \(Int(percentage.rounded()))% ngân sách \(budget.category.name)."
            } else {
                milestone = nil
                body = ""
            }
            guard let milestone else { continue }

            let cycle = Int(range.0.timeIntervalSince1970)
            let identifier = "\(notificationPrefix).\(budget.id.uuidString).\(cycle).\(milestone)"
            guard !UserDefaults.standard.bool(forKey: identifier) else { continue }

            let content = UNMutableNotificationContent()
            content.title = milestone == "over" ? "Vượt ngân sách" : "Cảnh báo ngân sách"
            content.body = body
            content.sound = .default
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                UserDefaults.standard.set(true, forKey: identifier)
            } catch { }
        }
    }
}

import Foundation
import Combine

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [FinanceTransaction]
    @Published private(set) var budgets: [SpendingBudget]
    @Published private(set) var preferences: FinancePreferences

    private let defaults: UserDefaults
    private let transactionsKey = "finance.transactions.v1"
    private let budgetsKey = "finance.budgets.v1"
    private let preferencesKey = "finance.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.transactions = Self.decode([FinanceTransaction].self, from: defaults, key: "finance.transactions.v1") ?? []
        self.budgets = Self.decode([SpendingBudget].self, from: defaults, key: "finance.budgets.v1") ?? []
        self.preferences = Self.decode(FinancePreferences.self, from: defaults, key: "finance.preferences.v1") ?? FinancePreferences()
    }

    var balance: Double {
        preferences.openingBalance + transactions.reduce(0) { total, transaction in
            total + (transaction.type == .income ? transaction.amount : -transaction.amount)
        }
    }

    func transactions(in month: Date, calendar: Calendar = .current) -> [FinanceTransaction] {
        transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func total(for type: TransactionType, in month: Date, calendar: Calendar = .current) -> Double {
        transactions(in: month, calendar: calendar)
            .filter { $0.type == type }
            .reduce(0) { $0 + $1.amount }
    }

    func spent(for category: FinanceCategory, in month: Date, calendar: Calendar = .current) -> Double {
        transactions(in: month, calendar: calendar)
            .filter { $0.type == .expense && $0.category == category }
            .reduce(0) { $0 + $1.amount }
    }

    func addOrUpdate(_ transaction: FinanceTransaction) {
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
        } else {
            transactions.append(transaction)
        }
        persist(transactions, key: transactionsKey)
    }

    func deleteTransaction(id: UUID) {
        transactions.removeAll { $0.id == id }
        persist(transactions, key: transactionsKey)
    }

    func setBudget(_ budget: SpendingBudget) {
        budgets.removeAll { $0.id == budget.id || $0.category == budget.category }
        budgets.append(budget)
        persist(budgets, key: budgetsKey)
    }

    func deleteBudget(id: UUID) {
        budgets.removeAll { $0.id == id }
        persist(budgets, key: budgetsKey)
    }

    func updatePreferences(_ update: (inout FinancePreferences) -> Void) {
        update(&preferences)
        persist(preferences, key: preferencesKey)
    }

    func clearAllData() {
        transactions = []
        budgets = []
        preferences = FinancePreferences()
        defaults.removeObject(forKey: transactionsKey)
        defaults.removeObject(forKey: budgetsKey)
        defaults.removeObject(forKey: preferencesKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

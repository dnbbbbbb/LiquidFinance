import Foundation
import Combine

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [FinanceTransaction]
    @Published private(set) var budgets: [SpendingBudget]
    @Published private(set) var preferences: FinancePreferences
    @Published private(set) var categories: [FinanceCategory]
    @Published private(set) var wallets: [FinanceWallet]

    private let defaults: UserDefaults
    private let transactionsKey = "finance.transactions.v1"
    private let budgetsKey = "finance.budgets.v1"
    private let preferencesKey = "finance.preferences.v1"
    private let categoriesKey = "finance.categories.v1"
    private let walletsKey = "finance.wallets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedTransactions = Self.decode([FinanceTransaction].self, from: defaults, key: "finance.transactions.v1") ?? []
        self.transactions = loadedTransactions
        self.budgets = Self.decode([SpendingBudget].self, from: defaults, key: "finance.budgets.v1") ?? []
        self.preferences = Self.decode(FinancePreferences.self, from: defaults, key: "finance.preferences.v1") ?? FinancePreferences()
        self.categories = Self.decode([FinanceCategory].self, from: defaults, key: "finance.categories.v1") ?? FinanceCategory.defaults
        var loadedWallets = Self.decode([FinanceWallet].self, from: defaults, key: "finance.wallets.v1") ?? [FinanceWallet(name: "Tiền mặt"), FinanceWallet(name: "Tài khoản ngân hàng", kind: "Tài khoản ngân hàng")]
        for legacyName in Set(loadedTransactions.map(\.account)) where !loadedWallets.contains(where: { $0.name == legacyName }) {
            loadedWallets.append(FinanceWallet(name: legacyName, kind: "Nguồn tiền khác"))
        }
        self.wallets = loadedWallets
    }

    var balance: Double {
        preferences.openingBalance + wallets.reduce(0) { $0 + $1.openingBalance } + transactions.reduce(0) { total, transaction in
            total + (transaction.type == .income ? transaction.amount : -transaction.amount)
        }
    }

    func balance(for wallet: FinanceWallet) -> Double {
        wallet.openingBalance + transactions.filter { $0.walletID == wallet.id || ($0.walletID == nil && $0.account == wallet.name) }
            .reduce(0) { $0 + ($1.type == .income ? $1.amount : -$1.amount) }
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
        let categoryIDs = Set([category.id] + categories.filter { $0.parentID == category.id }.map(\.id))
        transactions(in: month, calendar: calendar)
            .filter { $0.type == .expense && categoryIDs.contains($0.category.id) }
            .reduce(0) { $0 + $1.amount }
    }

    func categories(for type: TransactionType) -> [FinanceCategory] { categories.filter { $0.type == type } }

    func saveCategory(_ category: FinanceCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) { categories[index] = category }
        else { categories.append(category) }
        for index in categories.indices where categories[index].parentID == category.id { categories[index].type = category.type }
        for index in transactions.indices where transactions[index].category.id == category.id { transactions[index].category = category }
        for index in budgets.indices where budgets[index].category.id == category.id { budgets[index].category = category }
        persist(categories, key: categoriesKey); persist(transactions, key: transactionsKey); persist(budgets, key: budgetsKey)
    }

    func deleteCategory(id: String) {
        guard id != FinanceCategory.other.id && id != FinanceCategory.incomeOther.id else { return }
        let descendants = Set(categories.filter { $0.parentID == id }.map(\.id) + [id])
        categories.removeAll { descendants.contains($0.id) }
        for index in transactions.indices where descendants.contains(transactions[index].category.id) {
            transactions[index].category = categories.first(where: { $0.id == (transactions[index].type == .expense ? FinanceCategory.other.id : FinanceCategory.incomeOther.id) }) ?? (transactions[index].type == .expense ? .other : .incomeOther)
        }
        budgets.removeAll { descendants.contains($0.category.id) }
        persist(categories, key: categoriesKey); persist(transactions, key: transactionsKey); persist(budgets, key: budgetsKey)
    }

    func saveWallet(_ wallet: FinanceWallet) {
        if let index = wallets.firstIndex(where: { $0.id == wallet.id }) { wallets[index] = wallet }
        else { wallets.append(wallet) }
        for index in transactions.indices where transactions[index].walletID == wallet.id { transactions[index].account = wallet.name }
        persist(wallets, key: walletsKey); persist(transactions, key: transactionsKey)
    }

    func deleteWallet(id: UUID) {
        guard wallets.count > 1 else { return }
        let fallback = wallets.first(where: { $0.id != id })!
        wallets.removeAll { $0.id == id }
        for index in transactions.indices where transactions[index].walletID == id {
            transactions[index].walletID = fallback.id
            transactions[index].account = fallback.name
        }
        persist(wallets, key: walletsKey); persist(transactions, key: transactionsKey)
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
        defaults.removeObject(forKey: categoriesKey)
        defaults.removeObject(forKey: walletsKey)
        categories = FinanceCategory.defaults
        wallets = [FinanceWallet(name: "Tiền mặt"), FinanceWallet(name: "Tài khoản ngân hàng", kind: "Tài khoản ngân hàng")]
    }

    func backupData() throws -> Data {
        try JSONEncoder().encode(FinanceBackup(transactions: transactions, budgets: budgets, preferences: preferences, categories: categories, wallets: wallets))
    }

    func restoreBackup(_ data: Data) throws {
        let backup = try JSONDecoder().decode(FinanceBackup.self, from: data)
        guard backup.schemaVersion == 1 else { throw FinanceBackupError.unsupportedVersion }
        transactions = backup.transactions; budgets = backup.budgets; preferences = backup.preferences
        categories = backup.categories; wallets = backup.wallets
        persist(transactions, key: transactionsKey); persist(budgets, key: budgetsKey); persist(preferences, key: preferencesKey)
        persist(categories, key: categoriesKey); persist(wallets, key: walletsKey)
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

struct FinanceBackup: Codable {
    var schemaVersion = 1
    var exportedAt = Date()
    var transactions: [FinanceTransaction]
    var budgets: [SpendingBudget]
    var preferences: FinancePreferences
    var categories: [FinanceCategory]
    var wallets: [FinanceWallet]
}

enum FinanceBackupError: Error { case unsupportedVersion }


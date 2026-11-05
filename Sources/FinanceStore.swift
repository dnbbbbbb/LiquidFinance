import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [FinanceTransaction]
    @Published private(set) var budgets: [SpendingBudget]
    @Published private(set) var preferences: FinancePreferences
    @Published private(set) var categories: [FinanceCategory]
    @Published private(set) var wallets: [FinanceWallet]
    @Published private(set) var recurringRules: [RecurringRule]

    private let defaults: UserDefaults
    private let transactionsKey = "finance.transactions.v1"
    private let budgetsKey = "finance.budgets.v1"
    private let preferencesKey = "finance.preferences.v1"
    private let categoriesKey = "finance.categories.v1"
    private let walletsKey = "finance.wallets.v1"
    private let recurringKey = "finance.recurring.v1"
    private let widgetDefaults = UserDefaults(suiteName: "group.vn.liquidfinance")
    static let didChangeNotification = Notification.Name("finance.data.didChange")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedTransactions = Self.decode([FinanceTransaction].self, from: defaults, key: "finance.transactions.v1") ?? []
        self.transactions = loadedTransactions
        self.budgets = Self.decode([SpendingBudget].self, from: defaults, key: "finance.budgets.v1") ?? []
        self.preferences = Self.decode(FinancePreferences.self, from: defaults, key: "finance.preferences.v1") ?? FinancePreferences()
        var loadedCategories = Self.decode([FinanceCategory].self, from: defaults, key: "finance.categories.v1") ?? FinanceCategory.defaults
        for category in FinanceCategory.defaults where !loadedCategories.contains(where: { $0.id == category.id }) {
            loadedCategories.append(category)
        }
        self.categories = loadedCategories
        var loadedWallets = Self.decode([FinanceWallet].self, from: defaults, key: "finance.wallets.v1") ?? [FinanceWallet(name: "Tiền mặt"), FinanceWallet(name: "Tài khoản ngân hàng", kind: "Tài khoản ngân hàng")]
        for legacyName in Set(loadedTransactions.map(\.account)) where !loadedWallets.contains(where: { $0.name == legacyName }) {
            loadedWallets.append(FinanceWallet(name: legacyName, kind: "Nguồn tiền khác"))
        }
        self.wallets = loadedWallets
        self.recurringRules = Self.decode([RecurringRule].self, from: defaults, key: "finance.recurring.v1") ?? []
        syncWidgetSnapshot()
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

    var mostRecentlyUsedWallet: FinanceWallet {
        let recent = transactions.filter { !$0.isInternalTransfer }.max { $0.date < $1.date }
        if let recent {
            if let id = recent.walletID, let wallet = wallets.first(where: { $0.id == id }) { return wallet }
            if let wallet = wallets.first(where: { $0.name == recent.account }) { return wallet }
        }
        return wallets.first ?? FinanceWallet(name: "Tiền mặt")
    }

    func transactions(in month: Date, calendar: Calendar = .current) -> [FinanceTransaction] {
        transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func transactions(from start: Date, through end: Date) -> [FinanceTransaction] {
        transactions.filter { $0.date >= min(start, end) && $0.date <= max(start, end) }
    }

    func total(for type: TransactionType, from start: Date, through end: Date) -> Double {
        transactions(from: start, through: end).filter { $0.type == type && !$0.isInternalTransfer && $0.includeInReports }.reduce(0) { $0 + $1.amount }
    }

    func total(for type: TransactionType, in month: Date, calendar: Calendar = .current) -> Double {
        transactions(in: month, calendar: calendar)
            .filter { $0.type == type && !$0.isInternalTransfer && $0.includeInReports }
            .reduce(0) { $0 + $1.amount }
    }

    func spent(for category: FinanceCategory, in month: Date, calendar: Calendar = .current) -> Double {
        let categoryIDs = Set([category.id] + categories.filter { $0.parentID == category.id }.map(\.id))
        return spent(categoryIDs: categoryIDs, from: FinanceDate.startOfMonth(containing: month, calendar: calendar), through: calendar.date(byAdding: DateComponents(month: 1, second: -1), to: FinanceDate.startOfMonth(containing: month, calendar: calendar)) ?? month)
    }

    func spent(for category: FinanceCategory, from start: Date, through end: Date) -> Double {
        let categoryIDs = Set([category.id] + categories.filter { $0.parentID == category.id }.map(\.id))
        return spent(categoryIDs: categoryIDs, from: start, through: end)
    }

    func reportSpent(for category: FinanceCategory, from start: Date, through end: Date) -> Double {
        let categoryIDs = Set([category.id] + categories.filter { $0.parentID == category.id }.map(\.id))
        return transactions(from: start, through: end)
            .filter { $0.type == .expense && !$0.isInternalTransfer && $0.includeInReports && categoryIDs.contains($0.category.id) }
            .reduce(0) { $0 + $1.amount }
    }

    private func spent(categoryIDs: Set<String>, from start: Date, through end: Date) -> Double {
        transactions(from: start, through: end)
            .filter { $0.type == .expense && !$0.isInternalTransfer && categoryIDs.contains($0.category.id) }
            .reduce(0) { $0 + $1.amount }
    }

    func spent(for budget: SpendingBudget, from start: Date, through end: Date) -> Double {
        let ids = Set(budget.categoryIDs + categories.filter { budget.categoryIDs.contains($0.parentID ?? "") }.map(\.id))
        return transactions(from: start, through: end).filter { $0.type == .expense && !$0.isInternalTransfer && ids.contains($0.category.id) }.reduce(0) { $0 + $1.amount }
    }

    func setRecurringRule(_ rule: RecurringRule) {
        if let index = recurringRules.firstIndex(where: { $0.id == rule.id }) { recurringRules[index] = rule }
        else { recurringRules.append(rule) }
        persist(recurringRules, key: recurringKey)
    }

    func deleteRecurringRule(id: UUID) {
        recurringRules.removeAll { $0.id == id }
        persist(recurringRules, key: recurringKey)
    }

    func processDueRecurringTransactions(now: Date = .now) {
        var changed = false
        for index in recurringRules.indices where recurringRules[index].isEnabled {
            var rule = recurringRules[index]
            var safetyCount = 0
            while rule.nextDate <= now && safetyCount < 500 {
                transactions.append(FinanceTransaction(title: rule.title, amount: rule.amount, date: rule.nextDate, type: rule.type, category: rule.category, account: rule.account, walletID: rule.walletID, recurrenceID: rule.id, note: rule.note))
                rule.nextDate = rule.frequency.next(after: rule.nextDate, weekday: rule.weekday)
                safetyCount += 1
                changed = true
            }
            recurringRules[index] = rule
        }
        if changed { persist(transactions, key: transactionsKey); persist(recurringRules, key: recurringKey) }
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
        if transaction.type == .expense && !transaction.isInternalTransfer {
            Task { await BudgetAlertService.evaluate(budgets: budgets, store: self, date: transaction.date) }
        }
    }

    func deleteTransaction(id: UUID) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        transactions.removeAll { $0.id == id || (transaction.transferID != nil && $0.transferID == transaction.transferID) }
        persist(transactions, key: transactionsKey)
    }

    func transfer(amount: Double, fee: Double = 0, from source: FinanceWallet, to destination: FinanceWallet, date: Date = .now, note: String = "") {
        guard amount > 0, source.id != destination.id else { return }
        let transferID = UUID()
        let title = "Chuyển khoản nội bộ"
        let suffix = note.trimmingCharacters(in: .whitespacesAndNewlines)
        transactions.append(FinanceTransaction(title: title, amount: amount, date: date, type: .expense, category: .other, account: source.name, walletID: source.id, transferID: transferID, isInternalTransfer: true, note: suffix, includeInReports: false))
        transactions.append(FinanceTransaction(title: title, amount: amount, date: date, type: .income, category: .incomeOther, account: destination.name, walletID: destination.id, transferID: transferID, isInternalTransfer: true, note: suffix, includeInReports: false))
        if fee > 0 {
            transactions.append(FinanceTransaction(title: "Phí chuyển khoản", amount: fee, date: date, type: .expense, category: categories.first(where: { $0.id == FinanceCategory.transferFee.id }) ?? .transferFee, account: source.name, walletID: source.id, note: suffix))
        }
        persist(transactions, key: transactionsKey)
        if fee > 0 { Task { await BudgetAlertService.evaluate(budgets: budgets, store: self, date: date) } }
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

    func syncBalanceVisibility(_ isHidden: Bool) {
        guard preferences.hidesBalance != isHidden else { return }
        preferences.hidesBalance = isHidden
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
        recurringRules = []
        defaults.removeObject(forKey: recurringKey)
        defaults.set(false, forKey: "isBalanceHidden")
        syncWidgetSnapshot()
    }

    func backupData() throws -> Data {
        try JSONEncoder().encode(FinanceBackup(transactions: transactions, budgets: budgets, preferences: preferences, categories: categories, wallets: wallets, recurringRules: recurringRules))
    }

    func restoreBackup(_ data: Data) throws {
        let backup = try JSONDecoder().decode(FinanceBackup.self, from: data)
        guard backup.schemaVersion == 1 else { throw FinanceBackupError.unsupportedVersion }
        transactions = backup.transactions; budgets = backup.budgets; preferences = backup.preferences
        categories = backup.categories; wallets = backup.wallets
        recurringRules = backup.recurringRules
        defaults.set(preferences.hidesBalance, forKey: "isBalanceHidden")
        persist(transactions, key: transactionsKey); persist(budgets, key: budgetsKey); persist(preferences, key: preferencesKey)
        persist(categories, key: categoriesKey); persist(wallets, key: walletsKey); persist(recurringRules, key: recurringKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        syncWidgetSnapshot()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func syncWidgetSnapshot() {
        widgetDefaults?.set(balance, forKey: "finance.widget.balance")
        widgetDefaults?.set(preferences.currencyCode, forKey: "finance.widget.currency")
        widgetDefaults?.set(preferences.hidesBalance, forKey: "finance.widget.hidesBalance")
        widgetDefaults?.set(Date.now, forKey: "finance.widget.updatedAt")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
    var recurringRules: [RecurringRule] = []

    init(schemaVersion: Int = 1, exportedAt: Date = .now, transactions: [FinanceTransaction], budgets: [SpendingBudget], preferences: FinancePreferences, categories: [FinanceCategory], wallets: [FinanceWallet], recurringRules: [RecurringRule] = []) {
        self.schemaVersion = schemaVersion; self.exportedAt = exportedAt; self.transactions = transactions
        self.budgets = budgets; self.preferences = preferences; self.categories = categories; self.wallets = wallets; self.recurringRules = recurringRules
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, exportedAt, transactions, budgets, preferences, categories, wallets, recurringRules }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        transactions = try values.decode([FinanceTransaction].self, forKey: .transactions)
        budgets = try values.decode([SpendingBudget].self, forKey: .budgets)
        preferences = try values.decode(FinancePreferences.self, forKey: .preferences)
        categories = try values.decode([FinanceCategory].self, forKey: .categories)
        wallets = try values.decode([FinanceWallet].self, forKey: .wallets)
        recurringRules = try values.decodeIfPresent([RecurringRule].self, forKey: .recurringRules) ?? []
    }
}

enum FinanceBackupError: Error { case unsupportedVersion }


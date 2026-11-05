import XCTest
@testable import LiquidFinance

@MainActor
final class FinanceStoreTests: XCTestCase {
    private func makeStore() -> (FinanceStore, UserDefaults, String) {
        let suite = "LiquidFinanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (FinanceStore(defaults: defaults), defaults, suite)
    }

    func testBalanceIncludesOpeningAmountAndIncomeLessExpenses() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.updatePreferences { $0.openingBalance = 2_000 }
        store.addOrUpdate(FinanceTransaction(title: "Lương", amount: 500, type: .income, category: .salary))
        store.addOrUpdate(FinanceTransaction(title: "Ăn trưa", amount: 125, type: .expense, category: .food))

        XCTAssertEqual(store.balance, 2_375, accuracy: 0.001)
    }

    func testMonthlyTotalsOnlyIncludeTransactionsInRequestedMonth() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.date(from: DateComponents(year: 2025, month: 4, day: 1))!
        let nextMonth = calendar.date(from: DateComponents(year: 2025, month: 5, day: 1))!
        store.addOrUpdate(FinanceTransaction(title: "Ăn", amount: 100, date: month, type: .expense, category: .food))
        store.addOrUpdate(FinanceTransaction(title: "Đi lại", amount: 50, date: nextMonth, type: .expense, category: .transport))

        XCTAssertEqual(store.total(for: .expense, in: month, calendar: calendar), 100, accuracy: 0.001)
        XCTAssertEqual(store.spent(for: .food, in: month, calendar: calendar), 100, accuracy: 0.001)
        XCTAssertEqual(store.transactions(in: month, calendar: calendar).count, 1)
    }

    func testEditingTransactionReplacesItInsteadOfDuplicating() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var transaction = FinanceTransaction(title: "Cà phê", amount: 40, type: .expense, category: .food)
        store.addOrUpdate(transaction)
        transaction.amount = 55
        store.addOrUpdate(transaction)

        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.transactions.first?.amount, 55)
    }

    func testTransactionsAndPreferencesPersistAcrossStoreInstances() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let transaction = FinanceTransaction(title: "Lương", amount: 8_000, type: .income, category: .salary)
        store.addOrUpdate(transaction)
        let budget = SpendingBudget(category: .food, monthlyLimit: 2_500)
        store.setBudget(budget)
        store.updatePreferences { $0.currencyCode = "USD" }

        let restored = FinanceStore(defaults: defaults)
        XCTAssertEqual(restored.transactions, [transaction])
        XCTAssertEqual(restored.budgets, [budget])
        XCTAssertEqual(restored.preferences.currencyCode, "USD")
    }

    func testBudgetIsUpdatedByCategoryAndCanBeDeleted() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = SpendingBudget(category: .food, monthlyLimit: 1_000)
        store.setBudget(original)
        store.setBudget(SpendingBudget(id: original.id, category: .food, monthlyLimit: 2_000))

        XCTAssertEqual(store.budgets.count, 1)
        XCTAssertEqual(store.budgets.first?.monthlyLimit, 2_000)
        store.deleteBudget(id: original.id)
        XCTAssertTrue(store.budgets.isEmpty)
    }

    func testClearAllDataRemovesPersistedRecordsAndPreferences() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addOrUpdate(FinanceTransaction(title: "Cà phê", amount: 40, type: .expense, category: .food))
        store.setBudget(SpendingBudget(category: .food, monthlyLimit: 1_000))
        store.updatePreferences { $0.currencyCode = "EUR" }

        store.clearAllData()
        let restored = FinanceStore(defaults: defaults)
        XCTAssertTrue(restored.transactions.isEmpty)
        XCTAssertTrue(restored.budgets.isEmpty)
        XCTAssertEqual(restored.preferences, FinancePreferences())
    }

    func testCategoryHierarchyCountsChildSpendingInParentBudget() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = FinanceCategory(name: "Gia đình", type: .expense)
        let child = FinanceCategory(name: "Thực phẩm", type: .expense, parentID: parent.id)
        store.saveCategory(parent)
        store.saveCategory(child)
        store.addOrUpdate(FinanceTransaction(title: "Chợ", amount: 300, type: .expense, category: child))

        XCTAssertEqual(store.spent(for: parent, in: .now), 300, accuracy: 0.001)
    }

    func testWalletBalanceAndBackupRestore() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let wallet = FinanceWallet(name: "Ví điện tử", openingBalance: 1_000)
        store.saveWallet(wallet)
        store.addOrUpdate(FinanceTransaction(title: "Nạp tiền", amount: 250, type: .income, category: .salary, account: wallet.name, walletID: wallet.id))
        XCTAssertEqual(store.balance(for: wallet), 1_250, accuracy: 0.001)

        let backup = try store.backupData()
        store.clearAllData()
        try store.restoreBackup(backup)
        XCTAssertEqual(store.wallets.first(where: { $0.id == wallet.id }), wallet)
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.balance(for: wallet), 1_250, accuracy: 0.001)
    }

    func testBackupRejectsUnsupportedSchemaVersion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var backup = FinanceBackup(transactions: [], budgets: [], preferences: FinancePreferences(), categories: [], wallets: [])
        backup.schemaVersion = 99
        let invalid = try JSONEncoder().encode(backup)
        XCTAssertThrowsError(try store.restoreBackup(invalid))
    }

    func testBackupTracksTheLatestLocalChangeForCloudSync() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.addOrUpdate(FinanceTransaction(title: "Cà phê", amount: 40, type: .expense, category: .food))

        let backup = try JSONDecoder().decode(FinanceBackup.self, from: store.backupData())
        XCTAssertGreaterThan(backup.exportedAt, .distantPast)
        XCTAssertEqual(backup.transactions.count, 1)
    }

    func testAmountInputParsesAndFormatsVietnameseSeparators() {
        XCTAssertEqual(AmountInput.parse("1.234.567"), 1_234_567)
        XCTAssertEqual(AmountInput.parse("1.234.567,50"), 1_234_567.5)
        XCTAssertEqual(AmountInput.format(1_234_567), "1.234.567")
    }

    func testTransactionTimeRangeIsInclusiveAndUnboundedDatesRemainAvailable() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)
        store.addOrUpdate(FinanceTransaction(title: "Trong khoảng", amount: 100, date: start.addingTimeInterval(1_800), type: .expense, category: .food))
        store.addOrUpdate(FinanceTransaction(title: "Ngoài khoảng", amount: 50, date: end.addingTimeInterval(1), type: .expense, category: .food))

        XCTAssertEqual(store.transactions(from: start, through: end).map(\.title), ["Trong khoảng"])
        XCTAssertEqual(store.transactions(from: .distantPast, through: .distantFuture).count, 2)
    }

    func testBudgetCanCoverMultipleCategoriesAndCountsEachOnce() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = FinanceCategory(name: "Nhà", type: .expense)
        let child = FinanceCategory(name: "Điện", type: .expense, parentID: parent.id)
        store.saveCategory(parent)
        store.saveCategory(child)
        let budget = SpendingBudget(category: parent, monthlyLimit: 2_000, categoryIDs: [parent.id, child.id, FinanceCategory.food.id])
        store.setBudget(budget)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        store.addOrUpdate(FinanceTransaction(title: "Hóa đơn", amount: 300, date: start, type: .expense, category: child))
        store.addOrUpdate(FinanceTransaction(title: "Bữa trưa", amount: 200, date: start, type: .expense, category: .food))

        XCTAssertEqual(store.spent(for: budget, from: start, through: end), 500, accuracy: 0.001)
    }

    func testRecurringTransactionsAreCreatedThroughCurrentTimeAndPersisted() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let rule = RecurringRule(title: "Tiền thuê nhà", amount: 1_000, type: .expense, category: .housing, walletID: nil, account: "Tiền mặt", note: "", frequency: .daily, nextDate: first)
        store.setRecurringRule(rule)
        store.processDueRecurringTransactions(now: first.addingTimeInterval(2 * 86_400))

        XCTAssertEqual(store.transactions.count, 3)
        XCTAssertEqual(store.recurringRules.first?.nextDate, first.addingTimeInterval(3 * 86_400))
        let restored = FinanceStore(defaults: defaults)
        XCTAssertEqual(restored.recurringRules, store.recurringRules)
    }

    func testWeekdayRecurrenceSkipsWeekend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(from: DateComponents(year: 2025, month: 1, day: 3, hour: 20))!
        let monday = calendar.date(from: DateComponents(year: 2025, month: 1, day: 6, hour: 20))!

        XCTAssertEqual(RecurrenceFrequency.weekdays.next(after: friday, calendar: calendar), monday)
    }

    func testInternalTransferChangesWalletBalancesWithoutChangingTotalBalance() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let cash = store.wallets[0]
        let bank = store.wallets[1]
        let originalBalance = store.balance

        store.transfer(amount: 250, from: cash, to: bank)

        XCTAssertEqual(store.transactions.count, 2)
        XCTAssertEqual(store.balance, originalBalance, accuracy: 0.001)
        XCTAssertEqual(store.balance(for: cash), -250, accuracy: 0.001)
        XCTAssertEqual(store.balance(for: bank), 250, accuracy: 0.001)
        XCTAssertEqual(store.total(for: .expense, in: .now), 0, accuracy: 0.001)
    }

    func testTransferFeeIsAnExpenseWhileTransferLegsAreExcludedFromReports() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let cash = store.wallets[0]
        let bank = store.wallets[1]

        store.transfer(amount: 250, from: cash, to: bank, fee: 15)

        XCTAssertEqual(store.transactions.count, 3)
        XCTAssertEqual(store.transactions.filter(\.isInternalTransfer).count, 2)
        XCTAssertEqual(store.transactions.first(where: { $0.category.id == FinanceCategory.transferFee.id })?.isInternalTransfer, false)
        XCTAssertEqual(store.total(for: .expense, in: .now), 15, accuracy: 0.001)
        XCTAssertEqual(store.balance, -15, accuracy: 0.001)
        XCTAssertEqual(store.balance(for: cash), -265, accuracy: 0.001)
        XCTAssertEqual(store.balance(for: bank), 250, accuracy: 0.001)
    }

    func testBudgetAlertSettingsPersistWithBudget() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let budget = SpendingBudget(category: .food, monthlyLimit: 1_000, alertThreshold: 0.9, alertsEnabled: false)

        store.setBudget(budget)

        XCTAssertEqual(FinanceStore(defaults: defaults).budgets.first?.alertThreshold ?? 0, 0.9, accuracy: 0.001)
        XCTAssertEqual(FinanceStore(defaults: defaults).budgets.first?.alertsEnabled, false)
    }

    func testBudgetPeriodRangeSupportsQuarterlyCycle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let may = calendar.date(from: DateComponents(year: 2025, month: 5, day: 20))!
        let range = BudgetPeriod.quarterly.range(containing: may, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: range.0), 4)
        XCTAssertEqual(calendar.component(.month, from: range.1), 6)
    }
}

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
}

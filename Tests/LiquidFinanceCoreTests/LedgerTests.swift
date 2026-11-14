import XCTest
@testable import LiquidFinanceCore

final class LedgerTests: XCTestCase {
    var db: Database!; var ledger: LedgerService!
    var cash: Account!; var bank: Account!

    override func setUpWithError() throws {
        db = try Database(path: ":memory:")
        try Migrations.migrate(db)
        ledger = LedgerService(db: db)
        try ledger.seedDefaultCategoriesIfNeeded()
        cash = Account(name: "Tiền mặt", kind: .cash, openingBalance: Money(100_000))
        bank = Account(name: "Ngân hàng", kind: .bank, openingBalance: Money(1_000_000))
        try ledger.saveAccount(cash); try ledger.saveAccount(bank)
    }

    func cat(_ kind: CategoryKind) throws -> Category { try ledger.categories(kind: kind).first { $0.parentId != nil }! }
    func bal(_ a: Account) throws -> Int64 { try ledger.balance(of: a.id).minor }

    func testMoneyFormatting() {
        XCTAssertEqual(Money(50_000).formatted(), "50.000 ₫")
        XCTAssertEqual(Money(12_500_000).formatted(), "12.500.000 ₫")
        XCTAssertEqual(Money(-1_250_000).formatted(), "-1.250.000 ₫")
        XCTAssertEqual(Money(0).formatted(), "0 ₫")
        XCTAssertEqual(Money.parse("1.250.000"), Money(1_250_000))
        XCTAssertNil(Money.parse("12a"))
    }

    func testIncomeExpenseBalance() throws {
        try ledger.add(.init(type: .income, amount: Money(500_000), accountId: cash.id, categoryId: try cat(.income).id))
        try ledger.add(.init(type: .expense, amount: Money(120_000), accountId: cash.id, categoryId: try cat(.expense).id))
        XCTAssertEqual(try bal(cash), 480_000)
    }

    func testTransferIsNeitherIncomeNorExpenseExceptFee() throws {
        let now = Date(); let range = (now.addingTimeInterval(-60), now.addingTimeInterval(60))
        let before = try ledger.totalBalance()
        try ledger.add(.init(type: .transfer, amount: Money(300_000), accountId: bank.id, toAccountId: cash.id, fee: Money(1_000), date: now))
        XCTAssertEqual(try bal(bank), 699_000); XCTAssertEqual(try bal(cash), 400_000)
        XCTAssertEqual(try ledger.totalBalance(), before - Money(1_000))
        let t = try ledger.totals(from: range.0, to: range.1)
        XCTAssertEqual(t.income, Money(0)); XCTAssertEqual(t.expense, Money(1_000))
    }

    func testEditAndDeleteRecalculate() throws {
        var tx = try ledger.add(.init(type: .expense, amount: Money(50_000), accountId: cash.id, categoryId: try cat(.expense).id))
        XCTAssertEqual(try bal(cash), 50_000)
        tx.amount = Money(20_000); tx.accountId = bank.id
        try ledger.update(tx)
        XCTAssertEqual(try bal(cash), 100_000); XCTAssertEqual(try bal(bank), 980_000)
        try ledger.delete(tx.id)
        XCTAssertEqual(try bal(bank), 1_000_000)
    }

    func testIdempotencyPreventsDuplicates() throws {
        let tx = FinanceTransaction(type: .expense, amount: Money(10_000), accountId: cash.id, idempotencyKey: "intent-1")
        try ledger.add(tx)
        var again = tx; again.id = UUID()
        let stored = try ledger.add(again)
        XCTAssertEqual(stored.id, tx.id)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM transactions"), 1)
        XCTAssertEqual(try bal(cash), 90_000)
    }

    func testValidationRules() throws {
        XCTAssertThrowsError(try ledger.add(.init(type: .expense, amount: Money(0), accountId: cash.id)))
        XCTAssertThrowsError(try ledger.add(.init(type: .transfer, amount: Money(5), accountId: cash.id, toAccountId: cash.id)))
        XCTAssertThrowsError(try ledger.add(.init(type: .expense, amount: Money(5), accountId: cash.id, categoryId: try cat(.income).id)))
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM transactions"), 0)
    }

    func testRefundReducesExpenseAndCannotExceedOriginal() throws {
        let now = Date()
        let e = try ledger.add(.init(type: .expense, amount: Money(100_000), accountId: cash.id, categoryId: try cat(.expense).id, date: now))
        try ledger.add(.init(type: .refund, amount: Money(30_000), accountId: cash.id, categoryId: e.categoryId, refundOfId: e.id, date: now))
        XCTAssertThrowsError(try ledger.add(.init(type: .refund, amount: Money(80_000), accountId: cash.id, refundOfId: e.id)))
        XCTAssertEqual(try bal(cash), 30_000)
        let t = try ledger.totals(from: now.addingTimeInterval(-5), to: now.addingTimeInterval(5))
        XCTAssertEqual(t.expense, Money(70_000))
        XCTAssertThrowsError(try ledger.delete(e.id))   // has refunds
    }

    func testAdjustmentAffectsBalanceNotReports() throws {
        let now = Date()
        try ledger.adjustBalance(account: cash.id, to: Money(250_000), date: now)
        XCTAssertEqual(try bal(cash), 250_000)
        let t = try ledger.totals(from: now.addingTimeInterval(-5), to: now.addingTimeInterval(5))
        XCTAssertEqual(t, PeriodTotals(income: Money(0), expense: Money(0)))
        XCTAssertNil(try ledger.adjustBalance(account: cash.id, to: Money(250_000)))
    }

    func testAccountWithHistoryCannotBeDeleted() throws {
        try ledger.add(.init(type: .income, amount: Money(1), accountId: cash.id))
        XCTAssertThrowsError(try ledger.deleteAccount(cash.id))
        let c = try cat(.expense)
        try ledger.add(.init(type: .expense, amount: Money(1), accountId: cash.id, categoryId: c.id))
        XCTAssertThrowsError(try ledger.deleteCategory(c.id))
    }

    func testSeedIsIdempotentAndRenameKeepsId() throws {
        let n = try ledger.categories().count
        try ledger.seedDefaultCategoriesIfNeeded()
        XCTAssertEqual(try ledger.categories().count, n)
        var c = try cat(.expense); let id = c.id
        c.name = "Renamed"; try ledger.saveCategory(c)
        try ledger.seedDefaultCategoriesIfNeeded()
        XCTAssertEqual(try ledger.categories().count, n)
        XCTAssertEqual(try ledger.categories().first { $0.id == id }?.name, "Renamed")
    }

    func testAtomicRollback() throws {
        XCTAssertThrowsError(try db.transaction {
            try ledger.add(.init(type: .income, amount: Money(5), accountId: cash.id))
            throw DBError("boom")
        })
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM transactions"), 0)
    }

    func testDebtPrincipalNotIncomeOrExpense() throws {
        let now = Date()
        let debt = UUID()
        try db.execute("INSERT INTO debts(id,direction,person,principal,startDate,createdAt) VALUES(?,?,?,?,?,?)", [debt, "borrowed", "An", 500_000, now, now])
        try ledger.add(.init(type: .debtIn, amount: Money(500_000), accountId: cash.id, debtId: debt, date: now))
        try ledger.add(.init(type: .debtOut, amount: Money(200_000), accountId: cash.id, debtId: debt, date: now))
        XCTAssertEqual(try bal(cash), 400_000)
        XCTAssertEqual(try ledger.totals(from: now.addingTimeInterval(-5), to: now.addingTimeInterval(5)), PeriodTotals(income: Money(0), expense: Money(0)))
    }

    func testPagingAndSearch() throws {
        for i in 0..<120 { try ledger.add(.init(type: .expense, amount: Money(Int64(1000 + i)), accountId: cash.id, title: i % 2 == 0 ? "cà phê" : "bún", date: Date(timeIntervalSince1970: Double(1_700_000_000 + i)))) }
        XCTAssertEqual(try ledger.page(.init(), limit: 50, offset: 100).count, 20)
        var q = TransactionQuery(); q.search = "cà phê"
        XCTAssertEqual(try ledger.page(q, limit: 200).count, 60)
    }

    func testMigrationRejectsNewerSchema() throws {
        try db.execute("PRAGMA user_version = 99")
        XCTAssertThrowsError(try Migrations.migrate(db))
    }
}

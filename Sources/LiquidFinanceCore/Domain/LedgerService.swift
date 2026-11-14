import Foundation

public enum LedgerError: Error, LocalizedError, Equatable {
    case invalidAmount, sameAccount, accountUnavailable, categoryMismatch
    case accountHasHistory, categoryInUse, notFound, refundExceedsOriginal, hasRefunds
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Số tiền không hợp lệ."
        case .sameAccount: return "Tài khoản nguồn và đích phải khác nhau."
        case .accountUnavailable: return "Tài khoản đã bị lưu trữ hoặc không tồn tại."
        case .categoryMismatch: return "Danh mục không phù hợp với loại giao dịch."
        case .accountHasHistory: return "Tài khoản có lịch sử giao dịch; hãy lưu trữ thay vì xóa."
        case .categoryInUse: return "Danh mục đã được sử dụng; hãy lưu trữ thay vì xóa."
        case .notFound: return "Không tìm thấy dữ liệu."
        case .refundExceedsOriginal: return "Số tiền hoàn vượt quá giao dịch gốc."
        case .hasRefunds: return "Giao dịch này có khoản hoàn tiền; hãy xóa khoản hoàn tiền trước."
        }
    }
}

public struct TransactionQuery: Sendable {
    public var search: String = ""
    public var types: Set<TransactionType> = []
    public var accountId: UUID?
    public var categoryId: UUID?
    public var from: Date?
    public var to: Date?   // exclusive
    public var onlyImportant = false
    public var sortByAmount = false
    public var ascending = false
    public init() {}
}

/// Domain service: every money-affecting rule lives here, every write is one atomic DB transaction.
/// Balances are DERIVED (opening + signed effects of transactions) and never stored, so editing or
/// deleting a transaction can never leave a stale balance.
public final class LedgerService: @unchecked Sendable {
    public let db: Database
    public init(db: Database) { self.db = db }

    // MARK: Accounts
    public func saveAccount(_ a: Account) throws {
        try db.execute("""
        INSERT INTO accounts(id,name,kind,icon,colorHex,openingBalance,note,createdAt,isActive,isHidden,isArchived,sortOrder)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name,kind=excluded.kind,icon=excluded.icon,colorHex=excluded.colorHex,
          openingBalance=excluded.openingBalance,note=excluded.note,isActive=excluded.isActive,isHidden=excluded.isHidden,
          isArchived=excluded.isArchived,sortOrder=excluded.sortOrder
        """, [a.id, a.name, a.kind.rawValue, a.icon, a.colorHex, a.openingBalance.minor, a.note, a.createdAt,
              a.isActive, a.isHidden, a.isArchived, a.sortOrder])
    }

    public func accounts(includeArchived: Bool = false) throws -> [Account] {
        try db.query("SELECT * FROM accounts \(includeArchived ? "" : "WHERE isArchived=0") ORDER BY sortOrder, createdAt").map(Self.account)
    }

    public func deleteAccount(_ id: UUID) throws {
        let n = try db.scalarInt("SELECT COUNT(*) FROM transactions WHERE accountId=? OR toAccountId=?", [id, id])
        guard n == 0 else { throw LedgerError.accountHasHistory }
        try db.execute("DELETE FROM accounts WHERE id=?", [id])
    }

    public func balance(of accountId: UUID) throws -> Money {
        guard let b = try balances()[accountId] else { throw LedgerError.notFound }
        return b
    }

    /// Balance of every account, computed in one SQL pass.
    public func balances() throws -> [UUID: Money] {
        let rows = try db.query("""
        SELECT a.id AS id, a.openingBalance + COALESCE((
          SELECT SUM(
            CASE WHEN t.accountId = a.id THEN
              CASE t.type WHEN 'income' THEN t.amount WHEN 'refund' THEN t.amount WHEN 'adjustment' THEN t.amount
                          WHEN 'debtIn' THEN t.amount WHEN 'expense' THEN -t.amount WHEN 'debtOut' THEN -t.amount
                          WHEN 'transfer' THEN -(t.amount + t.fee) END
            ELSE 0 END
            + CASE WHEN t.toAccountId = a.id AND t.type = 'transfer' THEN t.amount ELSE 0 END)
          FROM transactions t WHERE t.accountId = a.id OR t.toAccountId = a.id), 0) AS bal
        FROM accounts a
        """)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.uuid("id"), Money($0.int("bal"))) })
    }

    /// Total of all non-hidden, non-archived accounts.
    public func totalBalance() throws -> Money {
        let b = try balances()
        return try accounts().filter { !$0.isHidden }.reduce(Money(0)) { $0 + (b[$1.id] ?? Money(0)) }
    }

    /// Creates an `.adjustment` so the account balance becomes `target`. History is preserved.
    @discardableResult
    public func adjustBalance(account: UUID, to target: Money, date: Date = Date()) throws -> FinanceTransaction? {
        try db.transaction {
            let diff = target - (try balance(of: account))
            guard diff.minor != 0 else { return nil }
            let tx = FinanceTransaction(type: .adjustment, amount: diff, accountId: account, date: date, title: "Điều chỉnh số dư")
            try insert(tx)
            return tx
        }
    }

    // MARK: Categories
    public func saveCategory(_ c: Category) throws {
        try db.execute("""
        INSERT INTO categories(id,parentId,name,kind,icon,colorHex,sortOrder,isHidden,isArchived,systemKey) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET parentId=excluded.parentId,name=excluded.name,icon=excluded.icon,colorHex=excluded.colorHex,
          sortOrder=excluded.sortOrder,isHidden=excluded.isHidden,isArchived=excluded.isArchived
        """, [c.id, c.parentId, c.name, c.kind.rawValue, c.icon, c.colorHex, c.sortOrder, c.isHidden, c.isArchived, c.systemKey])
    }

    public func categories(kind: CategoryKind? = nil, includeArchived: Bool = false) throws -> [Category] {
        var w: [String] = []; var p: [SQLConvertible] = []
        if let kind { w.append("kind=?"); p.append(kind.rawValue) }
        if !includeArchived { w.append("isArchived=0") }
        let clause = w.isEmpty ? "" : "WHERE " + w.joined(separator: " AND ")
        return try db.query("SELECT * FROM categories \(clause) ORDER BY sortOrder, name", p).map(Self.category)
    }

    public func deleteCategory(_ id: UUID) throws {
        let used = try db.scalarInt("SELECT (SELECT COUNT(*) FROM transactions WHERE categoryId=?) + (SELECT COUNT(*) FROM categories WHERE parentId=?)", [id, id])
        guard used == 0 else { throw LedgerError.categoryInUse }
        try db.execute("DELETE FROM categories WHERE id=?", [id])
    }

    /// Idempotent: seeds by systemKey, safe to call at every launch.
    public func seedDefaultCategoriesIfNeeded() throws {
        try db.transaction {
            for (i, group) in DefaultCategories.all.enumerated() {
                let pid = try seedOne(key: group.key, parent: nil, name: group.name, kind: group.kind, icon: group.icon, color: group.color, order: i)
                for (j, child) in group.children.enumerated() {
                    _ = try seedOne(key: "\(group.key).\(j)", parent: pid, name: child, kind: group.kind, icon: group.icon, color: group.color, order: j)
                }
            }
        }
    }
    private func seedOne(key: String, parent: UUID?, name: String, kind: CategoryKind, icon: String, color: String, order: Int) throws -> UUID {
        if let r = try db.query("SELECT id FROM categories WHERE systemKey=?", [key]).first { return r.uuid("id") }
        let c = Category(parentId: parent, name: name, kind: kind, icon: icon, colorHex: color, sortOrder: order, systemKey: key)
        try saveCategory(c)
        return c.id
    }

    // MARK: Transactions
    /// Inserts atomically. Re-submitting the same idempotencyKey returns the stored transaction unchanged.
    @discardableResult
    public func add(_ tx: FinanceTransaction) throws -> FinanceTransaction {
        try db.transaction {
            if let key = tx.idempotencyKey,
               let r = try db.query("SELECT * FROM transactions WHERE idempotencyKey=?", [key]).first {
                return Self.transaction(r)
            }
            try validate(tx, isNew: true)
            try insert(tx)
            return tx
        }
    }

    public func update(_ tx: FinanceTransaction) throws {
        try db.transaction {
            guard try db.scalarInt("SELECT COUNT(*) FROM transactions WHERE id=?", [tx.id]) == 1 else { throw LedgerError.notFound }
            try validate(tx, isNew: false)
            try db.execute("""
            UPDATE transactions SET type=?,amount=?,accountId=?,toAccountId=?,fee=?,categoryId=?,debtId=?,refundOfId=?,date=?,
              title=?,note=?,place=?,tags=?,isImportant=?,updatedAt=? WHERE id=?
            """, [tx.type.rawValue, tx.amount.minor, tx.accountId, tx.toAccountId, tx.fee.minor, tx.categoryId, tx.debtId,
                  tx.refundOfId, tx.date, tx.title, tx.note, tx.place, tx.tags.joined(separator: ","), tx.isImportant, Date(), tx.id])
        }
    }

    public func delete(_ id: UUID) throws {
        try db.transaction {
            guard try db.scalarInt("SELECT COUNT(*) FROM transactions WHERE refundOfId=?", [id]) == 0 else { throw LedgerError.hasRefunds }
            try db.execute("UPDATE recurring_occurrences SET transactionId=NULL WHERE transactionId=?", [id])
            guard try db.execute("DELETE FROM transactions WHERE id=?", [id]) == 1 else { throw LedgerError.notFound }
        }
    }

    /// Duplicate: new id, no idempotency key, date = now.
    @discardableResult
    public func duplicate(_ id: UUID, on date: Date = Date()) throws -> FinanceTransaction {
        guard let r = try db.query("SELECT * FROM transactions WHERE id=?", [id]).first else { throw LedgerError.notFound }
        var t = Self.transaction(r)
        t.id = UUID(); t.idempotencyKey = nil; t.date = date; t.createdAt = Date(); t.updatedAt = Date(); t.refundOfId = nil
        return try add(t)
    }

    public func transaction(id: UUID) throws -> FinanceTransaction? {
        try db.query("SELECT * FROM transactions WHERE id=?", [id]).first.map(Self.transaction)
    }

    /// Keyset-friendly paging; never loads the whole table.
    public func page(_ q: TransactionQuery, limit: Int = 50, offset: Int = 0) throws -> [FinanceTransaction] {
        var w: [String] = []; var p: [SQLConvertible] = []
        let s = q.search.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty {
            let like = "%\(s)%"
            w.append("""
            (t.title LIKE ? OR t.note LIKE ? OR t.place LIKE ? OR t.tags LIKE ? OR CAST(t.amount AS TEXT) LIKE ?
             OR t.categoryId IN (SELECT id FROM categories WHERE name LIKE ?)
             OR t.accountId IN (SELECT id FROM accounts WHERE name LIKE ?))
            """)
            p += [like, like, like, like, like, like, like]
        }
        if !q.types.isEmpty { w.append("t.type IN (\(q.types.map { _ in "?" }.joined(separator: ",")))"); p += q.types.map { $0.rawValue } }
        if let a = q.accountId { w.append("(t.accountId=? OR t.toAccountId=?)"); p += [a, a] }
        if let c = q.categoryId { w.append("(t.categoryId=? OR t.categoryId IN (SELECT id FROM categories WHERE parentId=?))"); p += [c, c] }
        if let f = q.from { w.append("t.date >= ?"); p.append(f) }
        if let to = q.to { w.append("t.date < ?"); p.append(to) }
        if q.onlyImportant { w.append("t.isImportant=1") }
        let dir = q.ascending ? "ASC" : "DESC"
        let order = q.sortByAmount ? "t.amount \(dir), t.id" : "t.date \(dir), t.id"
        p += [limit, offset]
        let sql = "SELECT t.* FROM transactions t \(w.isEmpty ? "" : "WHERE " + w.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?"
        return try db.query(sql, p).map(Self.transaction)
    }

    // MARK: Reports
    /// Income/expense for [from, to). Transfers, debt principal and adjustments are excluded.
    /// Expense = expenses + transfer fees − refunds.
    public func totals(from: Date, to: Date, accountId: UUID? = nil) throws -> PeriodTotals {
        let acc = accountId == nil ? "" : "AND accountId = ?"
        var p: [SQLConvertible] = [from, to]; if let accountId { p.append(accountId) }
        let r = try db.query("""
        SELECT
          COALESCE(SUM(CASE WHEN type='income' THEN amount END),0) AS inc,
          COALESCE(SUM(CASE WHEN type='expense' THEN amount WHEN type='transfer' THEN fee WHEN type='refund' THEN -amount END),0) AS exp
        FROM transactions WHERE date >= ? AND date < ? \(acc)
        """, p).first
        return PeriodTotals(income: Money(r?.int("inc") ?? 0), expense: Money(r?.int("exp") ?? 0))
    }

    /// Net expense per category (refunds subtract) for [from, to).
    public func expenseByCategory(from: Date, to: Date) throws -> [(categoryId: UUID?, total: Money)] {
        try db.query("""
        SELECT categoryId, SUM(CASE WHEN type='expense' THEN amount WHEN type='refund' THEN -amount END) AS total
        FROM transactions WHERE type IN ('expense','refund') AND date >= ? AND date < ?
        GROUP BY categoryId ORDER BY total DESC
        """, [from, to]).map { ($0.optUUID("categoryId"), Money($0.int("total"))) }
    }

    // MARK: Internals
    private func insert(_ tx: FinanceTransaction) throws {
        try db.execute("""
        INSERT INTO transactions(id,type,amount,accountId,toAccountId,fee,categoryId,debtId,refundOfId,date,title,note,place,tags,
          isImportant,createdAt,updatedAt,idempotencyKey) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [tx.id, tx.type.rawValue, tx.amount.minor, tx.accountId, tx.toAccountId, tx.fee.minor, tx.categoryId, tx.debtId,
              tx.refundOfId, tx.date, tx.title, tx.note, tx.place, tx.tags.joined(separator: ","), tx.isImportant,
              tx.createdAt, tx.updatedAt, tx.idempotencyKey])
    }

    private func validate(_ tx: FinanceTransaction, isNew: Bool) throws {
        if tx.type == .adjustment { guard tx.amount.minor != 0 else { throw LedgerError.invalidAmount } }
        else { guard tx.amount.minor > 0 else { throw LedgerError.invalidAmount } }
        guard tx.fee.minor >= 0, tx.type == .transfer || tx.fee.minor == 0 else { throw LedgerError.invalidAmount }
        func usable(_ id: UUID) throws -> Bool {
            try db.scalarInt("SELECT COUNT(*) FROM accounts WHERE id=? AND isArchived=0 AND isActive=1", [id]) == 1
        }
        if isNew { guard try usable(tx.accountId) else { throw LedgerError.accountUnavailable } }
        if tx.type == .transfer {
            guard let to = tx.toAccountId else { throw LedgerError.accountUnavailable }
            guard to != tx.accountId else { throw LedgerError.sameAccount }
            if isNew { guard try usable(to) else { throw LedgerError.accountUnavailable } }
        }
        if let cid = tx.categoryId {
            guard let kind = try db.query("SELECT kind FROM categories WHERE id=?", [cid]).first?.text("kind") else { throw LedgerError.notFound }
            let expected: String? = switch tx.type {
                case .income: "income"
                case .expense, .refund: "expense"
                default: nil }
            guard let expected, expected == kind else { throw LedgerError.categoryMismatch }
        }
        if tx.type == .refund, let orig = tx.refundOfId {
            guard let o = try db.query("SELECT amount FROM transactions WHERE id=? AND type='expense'", [orig]).first else { throw LedgerError.notFound }
            let already = try db.scalarInt("SELECT COALESCE(SUM(amount),0) FROM transactions WHERE refundOfId=? AND id != ?", [orig, tx.id])
            guard already + tx.amount.minor <= o.int("amount") else { throw LedgerError.refundExceedsOriginal }
        }
    }

    static func account(_ r: Row) -> Account {
        Account(id: r.uuid("id"), name: r.text("name"), kind: AccountKind(rawValue: r.text("kind")) ?? .other, icon: r.text("icon"),
                colorHex: r.text("colorHex"), openingBalance: Money(r.int("openingBalance")), note: r.text("note"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(r.int("createdAt"))), isActive: r.bool("isActive"),
                isHidden: r.bool("isHidden"), isArchived: r.bool("isArchived"), sortOrder: Int(r.int("sortOrder")))
    }
    static func category(_ r: Row) -> Category {
        Category(id: r.uuid("id"), parentId: r.optUUID("parentId"), name: r.text("name"),
                 kind: CategoryKind(rawValue: r.text("kind")) ?? .expense, icon: r.text("icon"), colorHex: r.text("colorHex"),
                 sortOrder: Int(r.int("sortOrder")), isHidden: r.bool("isHidden"), isArchived: r.bool("isArchived"),
                 systemKey: r.optText("systemKey"))
    }
    static func transaction(_ r: Row) -> FinanceTransaction {
        FinanceTransaction(id: r.uuid("id"), type: TransactionType(rawValue: r.text("type")) ?? .expense, amount: Money(r.int("amount")),
                           accountId: r.uuid("accountId"), toAccountId: r.optUUID("toAccountId"), fee: Money(r.int("fee")),
                           categoryId: r.optUUID("categoryId"), debtId: r.optUUID("debtId"), refundOfId: r.optUUID("refundOfId"),
                           date: Date(timeIntervalSince1970: TimeInterval(r.int("date"))), title: r.text("title"), note: r.text("note"),
                           place: r.text("place"), tags: r.text("tags").split(separator: ",").map(String.init),
                           isImportant: r.bool("isImportant"),
                           createdAt: Date(timeIntervalSince1970: TimeInterval(r.int("createdAt"))),
                           updatedAt: Date(timeIntervalSince1970: TimeInterval(r.int("updatedAt"))),
                           idempotencyKey: r.optText("idempotencyKey"))
    }
}

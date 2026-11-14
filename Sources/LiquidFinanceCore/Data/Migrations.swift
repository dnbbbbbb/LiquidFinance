import Foundation

/// Versioned, forward-only migrations driven by PRAGMA user_version.
/// Each migration runs inside one transaction: it fully applies or not at all.
public enum Migrations {
    public static let currentVersion = 1

    static let steps: [Int: [String]] = [
        1: [
            """
            CREATE TABLE accounts(
              id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
              icon TEXT NOT NULL, colorHex TEXT NOT NULL,
              openingBalance INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
              createdAt INTEGER NOT NULL, isActive INTEGER NOT NULL DEFAULT 1,
              isHidden INTEGER NOT NULL DEFAULT 0, isArchived INTEGER NOT NULL DEFAULT 0,
              sortOrder INTEGER NOT NULL DEFAULT 0)
            """,
            """
            CREATE TABLE categories(
              id TEXT PRIMARY KEY, parentId TEXT REFERENCES categories(id) ON DELETE RESTRICT,
              name TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('income','expense')),
              icon TEXT NOT NULL, colorHex TEXT NOT NULL, sortOrder INTEGER NOT NULL DEFAULT 0,
              isHidden INTEGER NOT NULL DEFAULT 0, isArchived INTEGER NOT NULL DEFAULT 0,
              systemKey TEXT UNIQUE)
            """,
            """
            CREATE TABLE debts(
              id TEXT PRIMARY KEY, direction TEXT NOT NULL CHECK(direction IN ('borrowed','lent')),
              person TEXT NOT NULL, principal INTEGER NOT NULL CHECK(principal > 0),
              startDate INTEGER NOT NULL, dueDate INTEGER, note TEXT NOT NULL DEFAULT '',
              reminderEnabled INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL)
            """,
            """
            CREATE TABLE transactions(
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL CHECK(type IN ('income','expense','transfer','refund','adjustment','debtIn','debtOut')),
              amount INTEGER NOT NULL,
              accountId TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
              toAccountId TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
              fee INTEGER NOT NULL DEFAULT 0 CHECK(fee >= 0),
              categoryId TEXT REFERENCES categories(id) ON DELETE RESTRICT,
              debtId TEXT REFERENCES debts(id) ON DELETE RESTRICT,
              refundOfId TEXT REFERENCES transactions(id) ON DELETE RESTRICT,
              date INTEGER NOT NULL, title TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
              place TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '',
              isImportant INTEGER NOT NULL DEFAULT 0,
              createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
              idempotencyKey TEXT UNIQUE,
              CHECK(type = 'adjustment' OR amount > 0),
              CHECK(type != 'transfer' OR (toAccountId IS NOT NULL AND toAccountId != accountId)),
              CHECK(type = 'transfer' OR toAccountId IS NULL),
              CHECK(type = 'transfer' OR fee = 0))
            """,
            "CREATE INDEX idx_tx_date ON transactions(date DESC, id)",
            "CREATE INDEX idx_tx_account ON transactions(accountId)",
            "CREATE INDEX idx_tx_to ON transactions(toAccountId)",
            "CREATE INDEX idx_tx_cat ON transactions(categoryId)",
            """
            CREATE TABLE attachments(
              id TEXT PRIMARY KEY, transactionId TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
              fileName TEXT NOT NULL, mimeType TEXT NOT NULL, byteSize INTEGER NOT NULL,
              sha256 TEXT NOT NULL, createdAt INTEGER NOT NULL)
            """,
            "CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
            """
            CREATE TABLE budgets(
              id TEXT PRIMARY KEY, categoryId TEXT REFERENCES categories(id) ON DELETE RESTRICT,
              period TEXT NOT NULL CHECK(period IN ('week','month')),
              limitAmount INTEGER NOT NULL CHECK(limitAmount > 0),
              startDate INTEGER NOT NULL, endDate INTEGER,
              rollover INTEGER NOT NULL DEFAULT 0, thresholds TEXT NOT NULL DEFAULT '50,75,90,100')
            """,
            """
            CREATE TABLE goals(
              id TEXT PRIMARY KEY, name TEXT NOT NULL, targetAmount INTEGER NOT NULL CHECK(targetAmount > 0),
              startDate INTEGER NOT NULL, targetDate INTEGER, note TEXT NOT NULL DEFAULT '',
              imageName TEXT NOT NULL DEFAULT '', createdAt INTEGER NOT NULL)
            """,
            """
            CREATE TABLE goal_entries(
              id TEXT PRIMARY KEY, goalId TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
              amount INTEGER NOT NULL CHECK(amount != 0), date INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '')
            """,
            """
            CREATE TABLE recurring_rules(
              id TEXT PRIMARY KEY, title TEXT NOT NULL, type TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
              accountId TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
              toAccountId TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
              categoryId TEXT REFERENCES categories(id) ON DELETE RESTRICT,
              frequency TEXT NOT NULL, intervalCount INTEGER NOT NULL DEFAULT 1,
              startDate INTEGER NOT NULL, endDate INTEGER,
              status TEXT NOT NULL DEFAULT 'active', remindDaysBefore INTEGER NOT NULL DEFAULT 0)
            """,
            """
            CREATE TABLE recurring_occurrences(
              id TEXT PRIMARY KEY, ruleId TEXT NOT NULL REFERENCES recurring_rules(id) ON DELETE CASCADE,
              dueDate INTEGER NOT NULL,
              transactionId TEXT REFERENCES transactions(id) ON DELETE SET NULL,
              UNIQUE(ruleId, dueDate))
            """,
            "CREATE TABLE saved_filters(id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL)",
        ]
    ]

    public static func migrate(_ db: Database, to target: Int = currentVersion) throws {
        let from = db.userVersion
        guard from <= target else {
            throw DBError("Database schema v\(from) is newer than this app supports (v\(target)).")
        }
        for v in (from + 1)...max(from + 1, target) where v <= target {
            guard let stmts = steps[v] else { throw DBError("Missing migration to v\(v)") }
            try db.transaction {
                for s in stmts { try db.execute(s) }
                try db.setUserVersion(v)
            }
        }
    }
}

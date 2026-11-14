import Foundation

public enum AccountKind: String, Codable, CaseIterable, Sendable { case cash, bank, ewallet, savings, other }
public enum CategoryKind: String, Codable, CaseIterable, Sendable { case income, expense }

public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case income, expense, transfer
    case refund      // money back for an expense: +balance, reduces expense totals
    case adjustment  // signed balance correction: affects balance only
    case debtIn      // borrowed money received / debt collected: +balance, NOT income
    case debtOut     // money lent / debt repaid (principal): -balance, NOT expense

    /// Single source of truth for report classification.
    public var countsAsIncome: Bool { self == .income }
    public var countsAsExpense: Bool { self == .expense }
}

public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var icon: String
    public var colorHex: String
    public var openingBalance: Money
    public var note: String
    public var createdAt: Date
    public var isActive: Bool
    public var isHidden: Bool
    public var isArchived: Bool
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, kind: AccountKind, icon: String = "banknote",
                colorHex: String = "#0A84FF", openingBalance: Money = Money(0), note: String = "",
                createdAt: Date = Date(), isActive: Bool = true, isHidden: Bool = false,
                isArchived: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.kind = kind; self.icon = icon; self.colorHex = colorHex
        self.openingBalance = openingBalance; self.note = note; self.createdAt = createdAt
        self.isActive = isActive; self.isHidden = isHidden; self.isArchived = isArchived; self.sortOrder = sortOrder
    }
}

public struct Category: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var parentId: UUID?
    public var name: String
    public var kind: CategoryKind
    public var icon: String
    public var colorHex: String
    public var sortOrder: Int
    public var isHidden: Bool
    public var isArchived: Bool
    /// Stable key for seeded categories (so renames never create duplicates on re-seed).
    public var systemKey: String?

    public init(id: UUID = UUID(), parentId: UUID? = nil, name: String, kind: CategoryKind,
                icon: String = "tag", colorHex: String = "#8E8E93", sortOrder: Int = 0,
                isHidden: Bool = false, isArchived: Bool = false, systemKey: String? = nil) {
        self.id = id; self.parentId = parentId; self.name = name; self.kind = kind; self.icon = icon
        self.colorHex = colorHex; self.sortOrder = sortOrder; self.isHidden = isHidden
        self.isArchived = isArchived; self.systemKey = systemKey
    }
}

public struct FinanceTransaction: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var type: TransactionType
    /// > 0 for every type except `.adjustment` (signed).
    public var amount: Money
    public var accountId: UUID
    public var toAccountId: UUID?
    public var fee: Money
    public var categoryId: UUID?
    public var debtId: UUID?
    public var refundOfId: UUID?
    public var date: Date
    public var title: String
    public var note: String
    public var place: String
    public var tags: [String]
    public var isImportant: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Unique per user intent; saving the same intent twice is a no-op (duplicate prevention).
    public var idempotencyKey: String?

    public init(id: UUID = UUID(), type: TransactionType, amount: Money, accountId: UUID,
                toAccountId: UUID? = nil, fee: Money = Money(0), categoryId: UUID? = nil,
                debtId: UUID? = nil, refundOfId: UUID? = nil, date: Date = Date(), title: String = "",
                note: String = "", place: String = "", tags: [String] = [], isImportant: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), idempotencyKey: String? = nil) {
        self.id = id; self.type = type; self.amount = amount; self.accountId = accountId
        self.toAccountId = toAccountId; self.fee = fee; self.categoryId = categoryId; self.debtId = debtId
        self.refundOfId = refundOfId; self.date = date; self.title = title; self.note = note
        self.place = place; self.tags = tags; self.isImportant = isImportant
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.idempotencyKey = idempotencyKey
    }
}

public struct AttachmentRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var transactionId: UUID
    public var fileName: String
    public var mimeType: String
    public var byteSize: Int64
    public var sha256: String
    public var createdAt: Date
}

public struct PeriodTotals: Equatable, Sendable {
    public var income: Money
    public var expense: Money
    public var net: Money { income - expense }
    /// Savings rate in whole percent; 0 when there is no income.
    public var savingsRatePercent: Int { Money.percent(net, of: income) }
}

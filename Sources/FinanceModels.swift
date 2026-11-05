import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "Chi tiêu" : "Thu nhập" }
}

struct FinanceCategory: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var type: TransactionType
    var parentID: String?
    var symbol: String
    var rawValue: String { name }

    init(id: String = UUID().uuidString, name: String, type: TransactionType, parentID: String? = nil, symbol: String = "circle.grid.2x2.fill") {
        self.id = id
        self.name = name
        self.type = type
        self.parentID = parentID
        self.symbol = symbol
    }

    static let food = FinanceCategory(id: "food", name: "Ăn uống", type: .expense, symbol: "fork.knife")
    static let transport = FinanceCategory(id: "transport", name: "Di chuyển", type: .expense, symbol: "car.fill")
    static let shopping = FinanceCategory(id: "shopping", name: "Mua sắm", type: .expense, symbol: "bag.fill")
    static let housing = FinanceCategory(id: "housing", name: "Nhà ở", type: .expense, symbol: "house.fill")
    static let health = FinanceCategory(id: "health", name: "Sức khỏe", type: .expense, symbol: "cross.case.fill")
    static let entertainment = FinanceCategory(id: "entertainment", name: "Giải trí", type: .expense, symbol: "play.rectangle.fill")
    static let education = FinanceCategory(id: "education", name: "Giáo dục", type: .expense, symbol: "book.closed.fill")
    static let bills = FinanceCategory(id: "bills", name: "Hóa đơn", type: .expense, symbol: "bolt.fill")
    static let salary = FinanceCategory(id: "salary", name: "Lương", type: .income, symbol: "briefcase.fill")
    static let bonus = FinanceCategory(id: "bonus", name: "Thưởng", type: .income, symbol: "gift.fill")
    static let investment = FinanceCategory(id: "investment", name: "Đầu tư", type: .income, symbol: "chart.line.uptrend.xyaxis")
    static let gift = FinanceCategory(id: "gift", name: "Quà tặng", type: .income, symbol: "heart.fill")
    static let other = FinanceCategory(id: "other-expense", name: "Khác", type: .expense)
    static let incomeOther = FinanceCategory(id: "other-income", name: "Khác", type: .income)

    static var expenseCategories: [FinanceCategory] { defaults.filter { $0.type == .expense } }
    static var incomeCategories: [FinanceCategory] { defaults.filter { $0.type == .income } }
    static var defaults: [FinanceCategory] { [food, transport, shopping, housing, health, entertainment, education, bills, salary, bonus, investment, gift, other, incomeOther] }

    private enum CodingKeys: String, CodingKey { case id, name, type, parentID, symbol }

    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            let existing = Self.defaults.first { $0.name == legacy && $0.type == .expense }
            let match = existing ?? Self.defaults.first { $0.name == legacy && $0.type == .income }
            guard let match else {
                self.init(name: legacy, type: .expense)
                return
            }
            self = match
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(TransactionType.self, forKey: .type)
        parentID = try values.decodeIfPresent(String.self, forKey: .parentID)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "circle.grid.2x2.fill"
    }
}

struct FinanceTransaction: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var amount: Double
    var date: Date
    var type: TransactionType
    var category: FinanceCategory
    var account: String
    var walletID: UUID?
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = .now,
        type: TransactionType,
        category: FinanceCategory,
        account: String = "Tiền mặt",
        walletID: UUID? = nil,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.type = type
        self.category = category
        self.account = account
        self.walletID = walletID
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case id, title, amount, date, type, category, account, walletID, note }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        amount = try values.decode(Double.self, forKey: .amount)
        date = try values.decode(Date.self, forKey: .date)
        type = try values.decode(TransactionType.self, forKey: .type)
        let decodedCategory = try values.decode(FinanceCategory.self, forKey: .category)
        category = type == .income && decodedCategory.id == FinanceCategory.other.id ? .incomeOther : decodedCategory
        account = try values.decodeIfPresent(String.self, forKey: .account) ?? "Tiền mặt"
        walletID = try values.decodeIfPresent(UUID.self, forKey: .walletID)
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct FinanceWallet: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var kind: String
    var openingBalance: Double
    init(id: UUID = UUID(), name: String, kind: String = "Ví tiền mặt", openingBalance: Double = 0) {
        self.id = id; self.name = name; self.kind = kind; self.openingBalance = openingBalance
    }
}

struct SpendingBudget: Identifiable, Codable, Equatable {
    var id: UUID
    var category: FinanceCategory
    var monthlyLimit: Double

    init(id: UUID = UUID(), category: FinanceCategory, monthlyLimit: Double) {
        self.id = id
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}

struct FinancePreferences: Codable, Equatable {
    var currencyCode: String = "VND"
    var openingBalance: Double = 0
    var hidesBalance: Bool = false
    var appearance: String = "system"

    private enum CodingKeys: String, CodingKey { case currencyCode, openingBalance, hidesBalance, appearance }
    init() { }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "VND"
        openingBalance = try values.decodeIfPresent(Double.self, forKey: .openingBalance) ?? 0
        hidesBalance = try values.decodeIfPresent(Bool.self, forKey: .hidesBalance) ?? false
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
    }
}

enum FinanceDate {
    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func isInSameMonth(_ firstDate: Date, as secondDate: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(firstDate, equalTo: secondDate, toGranularity: .month)
    }
}


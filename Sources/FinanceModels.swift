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
    var colorHex: UInt32?
    var rawValue: String { name }

    init(id: String = UUID().uuidString, name: String, type: TransactionType, parentID: String? = nil, symbol: String = "circle.grid.2x2.fill", colorHex: UInt32? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.parentID = parentID
        self.symbol = symbol
        self.colorHex = colorHex
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
    static let transferFee = FinanceCategory(id: "transfer-fee", name: "Phí chuyển khoản", type: .expense, symbol: "creditcard.and.123")

    static var expenseCategories: [FinanceCategory] { defaults.filter { $0.type == .expense } }
    static var incomeCategories: [FinanceCategory] { defaults.filter { $0.type == .income } }
    static var defaults: [FinanceCategory] { [food, transport, shopping, housing, health, entertainment, education, bills, transferFee, salary, bonus, investment, gift, other, incomeOther] }

    private enum CodingKeys: String, CodingKey { case id, name, type, parentID, symbol, colorHex }

    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            let existing = Self.defaults.first { $0.name == legacy && $0.type == .expense }
            let match = existing ?? Self.defaults.first { $0.name == legacy && $0.type == .income }
            self = match ?? FinanceCategory(name: legacy, type: .expense)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(String.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            type: try values.decode(TransactionType.self, forKey: .type),
            parentID: try values.decodeIfPresent(String.self, forKey: .parentID),
            symbol: try values.decodeIfPresent(String.self, forKey: .symbol) ?? "circle.grid.2x2.fill",
            colorHex: try values.decodeIfPresent(UInt32.self, forKey: .colorHex)
        )
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
    var recurrenceID: UUID?
    var transferID: UUID?
    var isInternalTransfer: Bool
    var note: String
    var includeInReports: Bool

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = .now,
        type: TransactionType,
        category: FinanceCategory,
        account: String = "Tiền mặt",
        walletID: UUID? = nil,
        recurrenceID: UUID? = nil,
        transferID: UUID? = nil,
        isInternalTransfer: Bool = false,
        note: String = "",
        includeInReports: Bool = true
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.type = type
        self.category = category
        self.account = account
        self.walletID = walletID
        self.recurrenceID = recurrenceID
        self.transferID = transferID
        self.isInternalTransfer = isInternalTransfer
        self.note = note
        self.includeInReports = includeInReports
    }

    private enum CodingKeys: String, CodingKey { case id, title, amount, date, type, category, account, walletID, recurrenceID, transferID, isInternalTransfer, note, includeInReports }

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
        recurrenceID = try values.decodeIfPresent(UUID.self, forKey: .recurrenceID)
        transferID = try values.decodeIfPresent(UUID.self, forKey: .transferID)
        isInternalTransfer = try values.decodeIfPresent(Bool.self, forKey: .isInternalTransfer) ?? transferID != nil
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        includeInReports = try values.decodeIfPresent(Bool.self, forKey: .includeInReports) ?? true
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
    var categoryIDs: [String]
    var period: BudgetPeriod
    var alertThreshold: Int
    var alertsEnabled: Bool

    init(id: UUID = UUID(), category: FinanceCategory, monthlyLimit: Double, categoryIDs: [String]? = nil, period: BudgetPeriod = .monthly, alertThreshold: Int = 80, alertsEnabled: Bool = false) {
        self.id = id
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.categoryIDs = categoryIDs ?? [category.id]
        self.period = period
        self.alertThreshold = alertThreshold
        self.alertsEnabled = alertsEnabled
    }

    private enum CodingKeys: String, CodingKey { case id, category, monthlyLimit, categoryIDs, period, alertThreshold, alertsEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        category = try values.decode(FinanceCategory.self, forKey: .category)
        monthlyLimit = try values.decode(Double.self, forKey: .monthlyLimit)
        categoryIDs = try values.decodeIfPresent([String].self, forKey: .categoryIDs) ?? [category.id]
        period = try values.decodeIfPresent(BudgetPeriod.self, forKey: .period) ?? .monthly
        alertThreshold = try values.decodeIfPresent(Int.self, forKey: .alertThreshold) ?? 80
        alertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? false
    }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly
    var id: String { rawValue }
    var title: String {
        switch self { case .weekly: return "Tuần"; case .monthly: return "Tháng"; case .quarterly: return "Quý"; case .yearly: return "Năm" }
    }

    func range(containing date: Date, calendar: Calendar = .current) -> (Date, Date) {
        let start: Date
        switch self {
        case .weekly:
            start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .monthly:
            start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .quarterly:
            let parts = calendar.dateComponents([.year, .month], from: date)
            let quarterMonth = (((parts.month ?? 1) - 1) / 3) * 3 + 1
            start = calendar.date(from: DateComponents(year: parts.year, month: quarterMonth, day: 1)) ?? date
        case .yearly:
            start = calendar.dateInterval(of: .year, for: date)?.start ?? date
        }
        let component: Calendar.Component = self == .weekly ? .weekOfYear : (self == .monthly ? .month : (self == .quarterly ? .month : .year))
        let value = self == .quarterly ? 3 : 1
        let next = calendar.date(byAdding: component, value: value, to: start) ?? start
        return (start, next.addingTimeInterval(-1))
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, biweekly, monthly, quarterly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "Hằng ngày"
        case .weekdays: return "Thứ Hai – Thứ Sáu"
        case .weekly: return "Hằng tuần"
        case .biweekly: return "Mỗi 2 tuần"
        case .monthly: return "Hằng tháng"
        case .quarterly: return "Mỗi quý"
        case .yearly: return "Hằng năm"
        }
    }
    func next(after date: Date, weekday: Int? = nil, calendar: Calendar = .current) -> Date {
        if (self == .weekly || self == .biweekly), let weekday {
            let currentWeekday = calendar.component(.weekday, from: date)
            var offset = (weekday - currentWeekday + 7) % 7
            if offset == 0 { offset = self == .biweekly ? 14 : 7 }
            else if self == .biweekly { offset += 7 }
            return calendar.date(byAdding: .day, value: offset, to: date) ?? date.addingTimeInterval(86_400)
        }
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next.addingTimeInterval(86_400)
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date.addingTimeInterval(86_400)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date.addingTimeInterval(86_400)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        }
    }
}

struct RecurringRule: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var amount: Double
    var type: TransactionType
    var category: FinanceCategory
    var walletID: UUID?
    var account: String
    var note: String
    var frequency: RecurrenceFrequency
    var weekday: Int?
    var nextDate: Date
    var isEnabled: Bool
    init(id: UUID = UUID(), title: String, amount: Double, type: TransactionType, category: FinanceCategory, walletID: UUID?, account: String, note: String, frequency: RecurrenceFrequency, weekday: Int? = nil, nextDate: Date, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.amount = amount; self.type = type; self.category = category
        self.walletID = walletID; self.account = account; self.note = note; self.frequency = frequency; self.weekday = weekday; self.nextDate = nextDate; self.isEnabled = isEnabled
    }
}

struct FinancePreferences: Codable, Equatable {
    var currencyCode: String = "VND"
    var openingBalance: Double = 0
    var hidesBalance: Bool = false
    var appearance: String = "system"
    var reminderEnabled: Bool = false
    var reminderHour: Int = 20
    var reminderMinute: Int = 0

    private enum CodingKeys: String, CodingKey { case currencyCode, openingBalance, hidesBalance, appearance, reminderEnabled, reminderHour, reminderMinute }
    init() { }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "VND"
        openingBalance = try values.decodeIfPresent(Double.self, forKey: .openingBalance) ?? 0
        hidesBalance = try values.decodeIfPresent(Bool.self, forKey: .hidesBalance) ?? false
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        reminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try values.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 20
        reminderMinute = try values.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
    }
}

enum FinanceDate {
    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func isInSameMonth(_ firstDate: Date, as secondDate: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(firstDate, equalTo: secondDate, toGranularity: .month)
    }

    static func weekdayTitle(_ value: Int) -> String {
        ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][max(1, min(value, 7)) - 1]
    }
}


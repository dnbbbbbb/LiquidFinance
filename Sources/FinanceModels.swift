import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "Chi tiêu" : "Thu nhập" }
}

enum FinanceCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Ăn uống"
    case transport = "Di chuyển"
    case shopping = "Mua sắm"
    case housing = "Nhà ở"
    case health = "Sức khỏe"
    case entertainment = "Giải trí"
    case education = "Giáo dục"
    case bills = "Hóa đơn"
    case salary = "Lương"
    case bonus = "Thưởng"
    case investment = "Đầu tư"
    case gift = "Quà tặng"
    case other = "Khác"

    var id: String { rawValue }

    static var expenseCategories: [FinanceCategory] {
        [.food, .transport, .shopping, .housing, .health, .entertainment, .education, .bills, .other]
    }

    static var incomeCategories: [FinanceCategory] {
        [.salary, .bonus, .investment, .gift, .other]
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .housing: return "house.fill"
        case .health: return "cross.case.fill"
        case .entertainment: return "play.rectangle.fill"
        case .education: return "book.closed.fill"
        case .bills: return "bolt.fill"
        case .salary: return "briefcase.fill"
        case .bonus: return "gift.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .gift: return "heart.fill"
        case .other: return "circle.grid.2x2.fill"
        }
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
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = .now,
        type: TransactionType,
        category: FinanceCategory,
        account: String = "Tiền mặt",
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.type = type
        self.category = category
        self.account = account
        self.note = note
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
}

enum FinanceDate {
    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func isInSameMonth(_ firstDate: Date, as secondDate: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(firstDate, equalTo: secondDate, toGranularity: .month)
    }
}

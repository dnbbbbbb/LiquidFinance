import Foundation
import UniformTypeIdentifiers

/// The only file formats accepted and produced by LiquidFinance.
/// They intentionally have their own identifiers and extensions so a random JSON or CSV file
/// cannot be mistaken for a complete financial record.
enum LiquidFinanceArchiveType {
    static let data = UTType(exportedAs: "vn.liquidfinance.data")
    static let backup = UTType(exportedAs: "vn.liquidfinance.backup")
}

enum LiquidFinanceArchiveKind: String, Codable, Equatable {
    case data
    case backup
}

struct LiquidFinanceDataPackage: Codable {
    var format = "LiquidFinance"
    var schemaVersion = 1
    var kind: LiquidFinanceArchiveKind = .data
    let createdAt: Date
    let transactions: [FinanceTransaction]
    let categories: [FinanceCategory]
    let wallets: [FinanceWallet]

    init(createdAt: Date = .now, transactions: [FinanceTransaction], categories: [FinanceCategory], wallets: [FinanceWallet]) {
        self.createdAt = createdAt
        self.transactions = transactions
        self.categories = categories
        self.wallets = wallets
    }
}

struct LiquidFinanceBackupPackage: Codable {
    var format = "LiquidFinance"
    var schemaVersion = 1
    var kind: LiquidFinanceArchiveKind = .backup
    let createdAt: Date
    let transactions: [FinanceTransaction]
    let budgets: [SpendingBudget]
    let preferences: FinancePreferences
    let categories: [FinanceCategory]
    let wallets: [FinanceWallet]
    let recurringRules: [RecurringRule]

    init(createdAt: Date = .now, transactions: [FinanceTransaction], budgets: [SpendingBudget], preferences: FinancePreferences, categories: [FinanceCategory], wallets: [FinanceWallet], recurringRules: [RecurringRule]) {
        self.createdAt = createdAt
        self.transactions = transactions
        self.budgets = budgets
        self.preferences = preferences
        self.categories = categories
        self.wallets = wallets
        self.recurringRules = recurringRules
    }
}

enum LiquidFinanceArchive {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func encode(_ package: LiquidFinanceDataPackage) throws -> Data { try encoder.encode(package) }
    static func encode(_ package: LiquidFinanceBackupPackage) throws -> Data { try encoder.encode(package) }

    static func decodeData(_ data: Data) throws -> LiquidFinanceDataPackage {
        do {
            let package = try JSONDecoder().decode(LiquidFinanceDataPackage.self, from: data)
            try validate(format: package.format, schemaVersion: package.schemaVersion, kind: package.kind, expected: .data)
            return package
        } catch let error as FinanceArchiveError {
            throw error
        } catch {
            throw FinanceArchiveError.notLiquidFinanceFile
        }
    }

    static func decodeBackup(_ data: Data) throws -> LiquidFinanceBackupPackage {
        do {
            let package = try JSONDecoder().decode(LiquidFinanceBackupPackage.self, from: data)
            try validate(format: package.format, schemaVersion: package.schemaVersion, kind: package.kind, expected: .backup)
            return package
        } catch let error as FinanceArchiveError {
            throw error
        } catch {
            throw FinanceArchiveError.notLiquidFinanceFile
        }
    }

    private static func validate(format: String, schemaVersion: Int, kind: LiquidFinanceArchiveKind, expected: LiquidFinanceArchiveKind) throws {
        guard format == "LiquidFinance" else { throw FinanceArchiveError.notLiquidFinanceFile }
        guard schemaVersion == 1 else { throw FinanceArchiveError.unsupportedVersion }
        guard kind == expected else { throw FinanceArchiveError.wrongFileType }
    }
}

enum FinanceArchiveError: LocalizedError {
    case notLiquidFinanceFile
    case unsupportedVersion
    case wrongFileType

    var errorDescription: String? {
        switch self {
        case .notLiquidFinanceFile: return "Tệp này không phải dữ liệu LiquidFinance hợp lệ."
        case .unsupportedVersion: return "Phiên bản tệp LiquidFinance này chưa được hỗ trợ."
        case .wrongFileType: return "Tệp không đúng loại dữ liệu bạn đã chọn."
        }
    }
}

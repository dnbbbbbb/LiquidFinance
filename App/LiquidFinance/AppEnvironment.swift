import SwiftUI
import UIKit
import LiquidFinanceCore

/// Composition root / dependency container.
@MainActor final class AppEnvironment: ObservableObject {
    let appDB: AppDatabase
    @Published private(set) var ledger: LedgerService
    @Published private(set) var settings: SettingsStore
    @Published var revision = 0   // bumped after writes/restore so views reload

    init() {
        let base = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        appDB = try! AppDatabase(paths: StoragePaths(root: base.appendingPathComponent("LiquidFinance")))
        ledger = LedgerService(db: appDB.current); settings = SettingsStore(db: appDB.current)
        try? ledger.seedDefaultCategoriesIfNeeded()
        if (try? ledger.accounts().isEmpty) == true {
            try? ledger.saveAccount(Account(name: "Tiền mặt", kind: .cash, icon: "banknote"))
        }
    }
    func reloadServices() {
        ledger = LedgerService(db: appDB.current); settings = SettingsStore(db: appDB.current); revision += 1
    }
}

// MARK: Alternate app icons (must be declared in Info.plist: CFBundleAlternateIcons)
enum AppIconChoice: String, CaseIterable, Identifiable {
    case `default` = "", pink = "AppIcon-Pink", pinkCute = "AppIcon-PinkCute", minimal = "AppIcon-Minimal",
         glass = "AppIcon-Glass", midnight = "AppIcon-Midnight", mint = "AppIcon-Mint", lavender = "AppIcon-Lavender"
    var id: String { rawValue }
    var title: String { ["": "Mặc định", "AppIcon-Pink": "Pink", "AppIcon-PinkCute": "Pink Cute", "AppIcon-Minimal": "Minimal",
                         "AppIcon-Glass": "Glass", "AppIcon-Midnight": "Midnight", "AppIcon-Mint": "Mint", "AppIcon-Lavender": "Lavender"][rawValue]! }
    @MainActor func apply() async throws {
        guard UIApplication.shared.supportsAlternateIcons else { throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Thiết bị không hỗ trợ đổi icon."]) }
        try await UIApplication.shared.setAlternateIconName(rawValue.isEmpty ? nil : rawValue)
    }
}

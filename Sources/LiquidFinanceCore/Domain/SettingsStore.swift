import Foundation

/// Key-value settings persisted in the same database, therefore included in every backup
/// (theme, accent, language, currency, dashboard layout, notification/security prefs).
public final class SettingsStore: @unchecked Sendable {
    public enum Key {
        public static let theme = "theme"                 // system|light|dark|pink
        public static let accent = "accentHex"
        public static let language = "language"
        public static let currency = "currency"
        public static let dashboardLayout = "dashboardLayout"   // JSON [{id,visible}]
        public static let appIcon = "appIcon"
        public static let autoBackup = "autoBackup"       // off|daily|weekly
        public static let backupRetention = "backupRetention"
        public static let lockTimeoutSeconds = "lockTimeoutSeconds"
        public static let hideBalances = "hideBalances"
        public static let lastUsedCategory = "lastUsedCategory"
        public static let lastUsedAccount = "lastUsedAccount"
    }
    private let db: Database
    public init(db: Database) { self.db = db }
    public func get(_ k: String) throws -> String? { try db.query("SELECT value FROM settings WHERE key=?", [k]).first?.text("value") }
    public func set(_ k: String, _ v: String) throws {
        try db.execute("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [k, v])
    }
    public func all() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try db.query("SELECT key,value FROM settings").map { ($0.text("key"), $0.text("value")) })
    }
}

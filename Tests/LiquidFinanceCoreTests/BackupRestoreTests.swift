import XCTest
@testable import LiquidFinanceCore

final class BackupRestoreTests: XCTestCase {
    var root: URL!; var app: AppDatabase!; var ledger: LedgerService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString)")
        app = try AppDatabase(paths: StoragePaths(root: root))
        ledger = LedgerService(db: app.current)
        app.onReplaced = { }
    }
    override func tearDownWithError() throws { app.closeCurrent(); try? FileManager.default.removeItem(at: root) }

    struct Snapshot: Equatable {
        var counts: [String: Int64]; var ids: [String: Set<String>]; var balances: [String: Int64]
        var income: Int64; var expense: Int64; var perCategory: [String: Int64]; var settings: [String: String]
        var attachmentHashes: [String: String]
    }

    /// Everything §3.9 asks to compare before/after restore.
    func snapshot(_ app: AppDatabase) throws -> Snapshot {
        let db = app.current; let l = LedgerService(db: db)
        var counts: [String: Int64] = [:]; var ids: [String: Set<String>] = [:]
        for t in ["accounts", "categories", "transactions", "attachments", "settings", "debts", "budgets", "goals"] {
            counts[t] = try db.scalarInt("SELECT COUNT(*) FROM \(t)")
            ids[t] = Set(try db.query("SELECT \(t == "settings" ? "key" : "id") AS k FROM \(t)").map { $0.text("k") })
        }
        let tot = try l.totals(from: .distantPast, to: .distantFuture)
        var per: [String: Int64] = [:]
        for r in try db.query("SELECT categoryId c, COUNT(*) n FROM transactions GROUP BY categoryId") { per[r.optText("c") ?? "-"] = r.int("n") }
        var hashes: [String: String] = [:]
        for a in try db.query("SELECT id FROM attachments") {
            hashes[a.text("id")] = BackupFormat.sha256Hex(try Data(contentsOf: app.paths.attachmentsDir.appendingPathComponent(a.text("id"))))
        }
        return Snapshot(counts: counts, ids: ids, balances: Dictionary(uniqueKeysWithValues: try l.balances().map { ($0.key.uuidString, $0.value.minor) }),
                        income: tot.income.minor, expense: tot.expense.minor, perCategory: per, settings: try SettingsStore(db: db).all(), attachmentHashes: hashes)
    }

    func populate(_ app: AppDatabase, transactions n: Int = 40, attachments: Int = 3) throws {
        let l = LedgerService(db: app.current)
        try l.seedDefaultCategoriesIfNeeded()
        let a = Account(name: "A", kind: .cash, openingBalance: Money(1_000_000)), b = Account(name: "B", kind: .bank)
        try l.saveAccount(a); try l.saveAccount(b)
        let ec = try l.categories(kind: .expense).first { $0.parentId != nil }!
        var last: FinanceTransaction!
        for i in 0..<n { last = try l.add(.init(type: i % 5 == 0 ? .transfer : .expense, amount: Money(Int64(1000 + i)), accountId: a.id,
                                              toAccountId: i % 5 == 0 ? b.id : nil, categoryId: i % 5 == 0 ? nil : ec.id,
                                              date: Date(timeIntervalSince1970: Double(1_700_000_000 + i * 3600)), note: "ghi chú \(i)")) }
        for i in 0..<attachments {
            let data = Data((0..<2048).map { UInt8(($0 &+ i) % 251) }); let id = UUID()
            try data.write(to: app.paths.attachmentsDir.appendingPathComponent(id.uuidString))
            try app.current.execute("INSERT INTO attachments(id,transactionId,fileName,mimeType,byteSize,sha256,createdAt) VALUES(?,?,?,?,?,?,?)",
                                    [id, last.id, "r\(i).jpg", "image/jpeg", data.count, BackupFormat.sha256Hex(data), Date()])
        }
        let s = SettingsStore(db: app.current); try s.set("theme", "pink"); try s.set("accentHex", "#FF6EB4")
    }

    func newBackupURL(_ name: String = UUID().uuidString) -> URL { root.appendingPathComponent("Backups/\(name).lfbackup") }

    func testRoundTripPlainSameDevice() throws {
        try populate(app)
        let before = try snapshot(app)
        let url = newBackupURL()
        let info = try BackupService.createBackup(from: app, to: url)
        XCTAssertEqual(info.manifest.transactionCount, 40); XCTAssertEqual(info.manifest.attachmentCount, 3)
        // mutate state after backup
        let l = LedgerService(db: app.current)
        try l.add(.init(type: .income, amount: Money(999), accountId: try l.accounts().first!.id))
        XCTAssertNotEqual(try snapshot(app), before)
        let prepared = try BackupService.prepareRestore(from: url, password: nil, paths: app.paths)
        try BackupService.restoreFull(prepared, into: app)
        XCTAssertEqual(try snapshot(app), before)
    }

    func testRoundTripOnDifferentDeviceEncrypted() throws {
        try populate(app, transactions: 25)
        let before = try snapshot(app)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url, password: "mật khẩu 123")
        let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent("lf-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let other = try AppDatabase(paths: StoragePaths(root: otherRoot))
        defer { other.closeCurrent() }
        try LedgerService(db: other.current).seedDefaultCategoriesIfNeeded()
        let info = try BackupService.inspect(url); XCTAssertTrue(info.isEncrypted)
        let prepared = try BackupService.prepareRestore(from: url, password: "mật khẩu 123", paths: other.paths)
        try BackupService.restoreFull(prepared, into: other)
        XCTAssertEqual(try snapshot(other), before)
    }

    func testWrongPasswordAndMissingPassword() throws {
        try populate(app, transactions: 3)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url, password: "right")
        XCTAssertThrowsError(try BackupService.prepareRestore(from: url, password: "wrong", paths: app.paths)) {
            XCTAssertEqual($0 as? BackupError, .wrongPasswordOrTampered) }
        XCTAssertThrowsError(try BackupService.prepareRestore(from: url, password: nil, paths: app.paths)) {
            XCTAssertEqual($0 as? BackupError, .passwordRequired) }
    }

    func testCorruptedFileRejectedAndCurrentDataUntouched() throws {
        try populate(app, transactions: 10)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url)
        var d = try Data(contentsOf: url); d[d.count - 100] ^= 0xFF; try d.write(to: url)
        let before = try snapshot(app)
        XCTAssertThrowsError(try BackupService.prepareRestore(from: url, password: nil, paths: app.paths))
        XCTAssertEqual(try snapshot(app), before)
    }

    func testEncryptedTamperDetected() throws {
        try populate(app, transactions: 5)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url, password: "pw")
        var d = try Data(contentsOf: url); d[d.count - 5] ^= 0x01; try d.write(to: url)
        XCTAssertThrowsError(try BackupService.prepareRestore(from: url, password: "pw", paths: app.paths))
    }

    func testTruncatedAndNotABackup() throws {
        let junk = newBackupURL("junk"); try Data("hello".utf8).write(to: junk)
        XCTAssertThrowsError(try BackupService.inspect(junk)) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        try populate(app, transactions: 5)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url)
        let d = try Data(contentsOf: url); try d.prefix(d.count / 2).write(to: url)
        XCTAssertThrowsError(try BackupService.prepareRestore(from: url, password: nil, paths: app.paths))
    }

    func testMissingAttachmentFailsBackupInsteadOfSilentlySkipping() throws {
        try populate(app, transactions: 3, attachments: 1)
        let f = try FileManager.default.contentsOfDirectory(at: app.paths.attachmentsDir, includingPropertiesForKeys: nil).first!
        try FileManager.default.removeItem(at: f)
        XCTAssertThrowsError(try BackupService.createBackup(from: app, to: newBackupURL()))
    }

    func testIncompatibleFutureFormatRejected() throws {
        try populate(app, transactions: 2)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url)
        let (h, _, payload) = try BackupFormat.decodeHeader(try Data(contentsOf: url))
        var future = h; future.magicVersion = 99
        try BackupFormat.encode(header: future, payload: payload).write(to: url)
        XCTAssertThrowsError(try BackupService.inspect(url)) { XCTAssertEqual($0 as? BackupError, .unsupportedFormat(99)) }
    }

    func testInterruptedRestoreIsRolledBackOnLaunch() throws {
        try populate(app, transactions: 6)
        let before = try snapshot(app)
        // simulate a crash after the swap began: rollback copies exist + marker
        app.closeCurrent()
        let p = app.paths
        try FileManager.default.copyItem(at: p.databaseURL, to: p.dbRollback)
        try FileManager.default.copyItem(at: p.attachmentsDir, to: p.attRollback)
        try Data("garbage".utf8).write(to: p.databaseURL)
        try Data().write(to: p.restoreMarker)
        app = try AppDatabase(paths: p)
        XCTAssertEqual(try snapshot(app), before)
    }

    func testRepeatedBackupsAndPruning() throws {
        try populate(app, transactions: 4)
        var last: URL!
        for i in 0..<4 {
            last = root.appendingPathComponent("Backups/b\(i).lfbackup")
            try BackupService.createBackup(from: app, to: last); Thread.sleep(forTimeInterval: 1.1)
        }
        XCTAssertEqual(BackupService.history(in: app.paths.backupsDir).count, 4)
        try BackupService.prune(in: app.paths.backupsDir, keep: 2, newest: last, password: nil)
        XCTAssertEqual(BackupService.history(in: app.paths.backupsDir).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: last.path))
    }

    func testLargeDataset() throws {
        try populate(app, transactions: 5000, attachments: 20)
        let before = try snapshot(app)
        let url = newBackupURL(); try BackupService.createBackup(from: app, to: url, password: "pw")
        let prepared = try BackupService.prepareRestore(from: url, password: "pw", paths: app.paths)
        try BackupService.restoreFull(prepared, into: app)
        XCTAssertEqual(try snapshot(app), before)
    }

    func testRestoreMigratesOlderSchemaIsNoOpAtV1() throws {
        try populate(app, transactions: 2)
        let url = newBackupURL(); let info = try BackupService.createBackup(from: app, to: url)
        XCTAssertEqual(info.manifest.databaseSchemaVersion, Migrations.currentVersion)
    }
}

import Foundation

public struct StoragePaths: Sendable {
    public let root: URL
    public var databaseURL: URL { root.appendingPathComponent("liquidfinance.sqlite") }
    public var attachmentsDir: URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    public var backupsDir: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public var stagingDir: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    var restoreMarker: URL { root.appendingPathComponent("restore.inprogress") }
    var dbRollback: URL { root.appendingPathComponent("liquidfinance.sqlite.rollback") }
    var attRollback: URL { root.appendingPathComponent("Attachments.rollback", isDirectory: true) }
    public init(root: URL) { self.root = root }
    func ensure() throws {
        for d in [root, attachmentsDir, backupsDir] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    }
}

/// Owns the live database connection so Restore can swap the file and reopen it.
public final class AppDatabase: @unchecked Sendable {
    public let paths: StoragePaths
    public private(set) var current: Database
    public var onReplaced: (@Sendable () -> Void)?

    public init(paths: StoragePaths) throws {
        self.paths = paths
        try paths.ensure()
        try BackupService.recoverInterruptedRestore(paths: paths)   // crash safety
        current = try Self.openMigrated(paths.databaseURL)
    }
    static func openMigrated(_ url: URL) throws -> Database {
        let db = try Database(path: url.path)
        try Migrations.migrate(db)
        return db
    }
    func reopen() throws { current = try Self.openMigrated(paths.databaseURL); onReplaced?() }
    func closeCurrent() { current.close() }
}

public struct BackupInfo: Sendable, Equatable {
    public var manifest: BackupManifest
    public var isEncrypted: Bool
    public var fileSize: Int64
    /// Honest labelling: SHA-256 proves integrity only. Authenticity needs AES-GCM (encrypted backups).
    public var authenticated: Bool { isEncrypted }
}

public struct PreparedBackup: Sendable {
    public let info: BackupInfo
    let stagingRoot: URL
    var stagedDB: URL { stagingRoot.appendingPathComponent("database.sqlite") }
    var stagedAttachments: URL { stagingRoot.appendingPathComponent("attachments", isDirectory: true) }
}

public typealias BackupProgress = @Sendable (Double, String) -> Void

public enum BackupService {
    public static let appVersion = "1.0.0"

    // MARK: Create
    /// Writes a fully verified .lfbackup. Success is only returned after the file was re-read and re-verified.
    @discardableResult
    public static func createBackup(from app: AppDatabase, to destination: URL, password: String? = nil,
                                    progress: BackupProgress? = nil) throws -> BackupInfo {
        let fm = FileManager.default
        let tmpDir = app.paths.stagingDir.appendingPathComponent("create-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        progress?(0.05, "Tạo ảnh chụp cơ sở dữ liệu")
        let snapshot = tmpDir.appendingPathComponent("snapshot.sqlite")
        try app.current.execute("VACUUM INTO ?", [snapshot.path])    // consistent point-in-time copy
        let snap = try Database(path: snapshot.path, readOnly: true)
        defer { snap.close() }
        let check = try snap.query("PRAGMA integrity_check").first?.text("integrity_check") ?? ""
        guard check == "ok" else { throw BackupError.integrityCheckFailed(check) }
        let dbData = try Data(contentsOf: snapshot)

        progress?(0.2, "Đóng gói tệp đính kèm")
        var entries: [(name: String, data: Data)] = [("database.sqlite", dbData)]
        var hashes: [String: String] = ["database.sqlite": BackupFormat.sha256Hex(dbData)]
        var total = Int64(dbData.count)
        let atts = try snap.query("SELECT id, sha256 FROM attachments ORDER BY id")
        for (i, a) in atts.enumerated() {
            let id = a.text("id")
            let url = app.paths.attachmentsDir.appendingPathComponent(id)
            guard let d = try? Data(contentsOf: url) else { throw BackupError.missingAttachment(id) }
            guard BackupFormat.sha256Hex(d) == a.text("sha256") else { throw BackupError.attachmentCorrupt(id) }
            entries.append(("attachments/\(id)", d)); hashes["attachments/\(id)"] = a.text("sha256"); total += Int64(d.count)
            progress?(0.2 + 0.3 * Double(i + 1) / Double(max(atts.count, 1)), "Đóng gói tệp đính kèm")
        }

        let manifest = BackupManifest(
            appName: "LiquidFinance", backupFormatVersion: BackupFormat.currentFormatVersion,
            databaseSchemaVersion: snap.userVersion, appVersion: appVersion, createdAt: Date(),
            accountCount: Int(try snap.scalarInt("SELECT COUNT(*) FROM accounts")),
            transactionCount: Int(try snap.scalarInt("SELECT COUNT(*) FROM transactions")),
            categoryCount: Int(try snap.scalarInt("SELECT COUNT(*) FROM categories")),
            attachmentCount: atts.count, totalBytes: total,
            databaseSHA256: hashes["database.sqlite"]!, deviceName: ProcessInfo.processInfo.hostName)
        let enc = BackupFormat.encoder()
        let manifestData = try enc.encode(manifest)
        hashes["manifest.json"] = BackupFormat.sha256Hex(manifestData)
        let integrity = try enc.encode(IntegrityFile(algorithm: "SHA-256", files: hashes))
        entries.insert(("manifest.json", manifestData), at: 0)
        entries.append(("integrity.json", integrity))

        progress?(0.55, password == nil ? "Ghi tệp" : "Mã hóa AES-GCM")
        let archive = try BackupFormat.packArchive(entries)
        var header = BackupHeader(magicVersion: BackupFormat.currentFormatVersion, encrypted: false, kdf: nil, manifest: manifest)
        var payload = archive
        if let password {
            header.encrypted = true; header.kdf = BackupFormat.newKDF()
            let key = try BackupFormat.deriveKey(password: password, kdf: header.kdf!)
            let aad = try BackupFormat.encoder().encode(header)
            payload = try BackupFormat.seal(archive, key: key, aad: aad)
        }
        let fileData = try BackupFormat.encode(header: header, payload: payload)

        try ensureSpace(for: fileData.count, at: destination.deletingLastPathComponent())
        let partial = destination.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        do {
            try fileData.write(to: partial, options: .atomic)
            progress?(0.8, "Xác minh tệp sao lưu")
            do { _ = try verifyFile(partial, password: password) }
            catch { throw BackupError.verificationFailed(error.localizedDescription) }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: partial, to: destination)
        } catch { try? fm.removeItem(at: partial); throw error }
        progress?(1, "Hoàn tất")
        return BackupInfo(manifest: manifest, isEncrypted: password != nil, fileSize: Int64(fileData.count))
    }

    public static func defaultFileName(date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return "LiquidFinance_Backup_\(f.string(from: date)).\(BackupFormat.fileExtension)"
    }

    // MARK: Inspect / verify
    /// Reads header only (no password needed). Validity is decided by content, never by file name.
    public static func inspect(_ url: URL) throws -> BackupInfo {
        let data = try Data(contentsOf: url)
        let (h, _, _) = try BackupFormat.decodeHeader(data)
        guard h.manifest.appName == "LiquidFinance" else { throw BackupError.notABackup }
        guard h.manifest.databaseSchemaVersion <= Migrations.currentVersion else { throw BackupError.unsupportedSchema(h.manifest.databaseSchemaVersion) }
        return BackupInfo(manifest: h.manifest, isEncrypted: h.encrypted, fileSize: Int64(data.count))
    }

    /// Decrypts and verifies every checksum, returning the verified entries.
    static func openEntries(_ url: URL, password: String?) throws -> (BackupInfo, [String: Data]) {
        let data = try Data(contentsOf: url)
        let (h, hb, payload) = try BackupFormat.decodeHeader(data)
        guard h.manifest.appName == "LiquidFinance" else { throw BackupError.notABackup }
        guard h.manifest.databaseSchemaVersion <= Migrations.currentVersion else { throw BackupError.unsupportedSchema(h.manifest.databaseSchemaVersion) }
        var archive = payload
        if h.encrypted {
            guard let password, let kdf = h.kdf else { throw BackupError.passwordRequired }
            archive = try BackupFormat.open(payload, key: try BackupFormat.deriveKey(password: password, kdf: kdf), aad: hb)
        }
        let entries = try BackupFormat.unpackArchive(archive)
        for n in ["manifest.json", "database.sqlite", "integrity.json"] where entries[n] == nil { throw BackupError.missingEntry(n) }
        guard let integrity = try? BackupFormat.decoder().decode(IntegrityFile.self, from: entries["integrity.json"]!) else { throw BackupError.notABackup }
        for (name, d) in entries where name != "integrity.json" {
            guard integrity.files[name] == BackupFormat.sha256Hex(d) else { throw BackupError.checksumMismatch(name) }
        }
        for name in integrity.files.keys where entries[name] == nil { throw BackupError.missingEntry(name) }
        guard let m = try? BackupFormat.decoder().decode(BackupManifest.self, from: entries["manifest.json"]!), m == h.manifest else {
            throw BackupError.manifestMismatch
        }
        return (BackupInfo(manifest: m, isEncrypted: h.encrypted, fileSize: Int64(data.count)), entries)
    }

    @discardableResult
    public static func verifyFile(_ url: URL, password: String?) throws -> BackupInfo { try openEntries(url, password: password).0 }

    // MARK: Prepare (steps 4-8: decrypt, checksum, stage, validate)
    public static func prepareRestore(from url: URL, password: String?, paths: StoragePaths,
                                      progress: BackupProgress? = nil) throws -> PreparedBackup {
        let fm = FileManager.default
        progress?(0.1, "Giải mã và xác minh checksum")
        let (info, entries) = try openEntries(url, password: password)
        let staging = paths.stagingDir.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        do {
            try ensureSpace(for: Int(info.manifest.totalBytes) * 2, at: paths.root)
            try fm.createDirectory(at: staging.appendingPathComponent("attachments"), withIntermediateDirectories: true)
            progress?(0.35, "Ghi vào vùng dữ liệu tạm")
            let prepared = PreparedBackup(info: info, stagingRoot: staging)
            try entries["database.sqlite"]!.write(to: prepared.stagedDB)
            for (n, d) in entries where n.hasPrefix("attachments/") {
                try d.write(to: staging.appendingPathComponent(n))
            }
            progress?(0.6, "Kiểm tra cơ sở dữ liệu")
            try validateStaged(prepared)
            return prepared
        } catch { try? fm.removeItem(at: staging); throw error }
    }

    public static func discard(_ p: PreparedBackup) { try? FileManager.default.removeItem(at: p.stagingRoot) }

    /// Validation of §3.4 items 3-7 on the staged copy (migrates it when older).
    static func validateStaged(_ p: PreparedBackup) throws {
        let db: Database
        do { db = try Database(path: p.stagedDB.path) } catch { throw BackupError.databaseUnreadable(error.localizedDescription) }
        defer { db.close() }
        do {
            try Migrations.migrate(db)   // staged copy only; runs inside transactions
            let ic = try db.query("PRAGMA integrity_check").first?.text("integrity_check") ?? ""
            guard ic == "ok" else { throw BackupError.integrityCheckFailed(ic) }
            let fk = try db.query("PRAGMA foreign_key_check")
            guard fk.isEmpty else { throw BackupError.integrityCheckFailed("\(fk.count) liên kết dữ liệu không hợp lệ") }
            for t in ["accounts", "transactions", "categories", "attachments", "settings"] {
                _ = try db.scalarInt("SELECT COUNT(*) FROM \(t)")   // table must exist
            }
            let m = p.info.manifest
            guard try db.scalarInt("SELECT COUNT(*) FROM accounts") == m.accountCount,
                  try db.scalarInt("SELECT COUNT(*) FROM transactions") == m.transactionCount,
                  try db.scalarInt("SELECT COUNT(*) FROM categories") == m.categoryCount,
                  try db.scalarInt("SELECT COUNT(*) FROM attachments") == m.attachmentCount else { throw BackupError.manifestMismatch }
            for a in try db.query("SELECT id, sha256 FROM attachments") {
                let f = p.stagedAttachments.appendingPathComponent(a.text("id"))
                guard let d = try? Data(contentsOf: f) else { throw BackupError.missingAttachment(a.text("id")) }
                guard BackupFormat.sha256Hex(d) == a.text("sha256") else { throw BackupError.attachmentCorrupt(a.text("id")) }
            }
        } catch let e as BackupError { throw e }
        catch { throw BackupError.databaseUnreadable(error.localizedDescription) }
    }

    // MARK: Full restore (steps 9-10)
    /// Replaces the current data with the prepared backup. Makes a verified safety backup first;
    /// the current database is never deleted until the new one has been reopened and validated.
    public static func restoreFull(_ prepared: PreparedBackup, into app: AppDatabase, safetyPassword: String? = nil,
                                   progress: BackupProgress? = nil) throws {
        let fm = FileManager.default
        let paths = app.paths
        progress?(0.7, "Tạo bản sao lưu dự phòng")
        let safetyDir = paths.backupsDir.appendingPathComponent("PreRestore", isDirectory: true)
        try fm.createDirectory(at: safetyDir, withIntermediateDirectories: true)
        try createBackup(from: app, to: safetyDir.appendingPathComponent("PreRestore_" + defaultFileName()), password: safetyPassword)

        progress?(0.8, "Thay thế dữ liệu")
        try? fm.removeItem(at: paths.dbRollback); try? fm.removeItem(at: paths.attRollback)
        try Data().write(to: paths.restoreMarker)          // crash-recovery journal
        app.closeCurrent()
        do {
            try fm.moveItem(at: paths.databaseURL, to: paths.dbRollback)
            try fm.moveItem(at: paths.attachmentsDir, to: paths.attRollback)
            try fm.moveItem(at: prepared.stagedDB, to: paths.databaseURL)
            try fm.moveItem(at: prepared.stagedAttachments, to: paths.attachmentsDir)
            try app.reopen()
            // post-swap verification against the manifest
            let db = app.current, m = prepared.info.manifest
            let ok = try db.scalarInt("SELECT COUNT(*) FROM transactions") == m.transactionCount
                && db.scalarInt("SELECT COUNT(*) FROM accounts") == m.accountCount
                && (try db.query("PRAGMA integrity_check").first?.text("integrity_check")) == "ok"
            guard ok else { throw BackupError.integrityCheckFailed("Kiểm tra sau khôi phục không khớp") }
        } catch {
            app.closeCurrent()
            try? rollbackSwap(paths)
            try? app.reopen()
            throw BackupError.restoreFailedRolledBack(error.localizedDescription)
        }
        try? fm.removeItem(at: paths.restoreMarker)       // commit point
        try? fm.removeItem(at: paths.dbRollback); try? fm.removeItem(at: paths.attRollback)
        discard(prepared)
        progress?(1, "Hoàn tất")
    }

    private static func rollbackSwap(_ paths: StoragePaths) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.dbRollback.path) {
            try? fm.removeItem(at: paths.databaseURL); try fm.moveItem(at: paths.dbRollback, to: paths.databaseURL)
        }
        if fm.fileExists(atPath: paths.attRollback.path) {
            try? fm.removeItem(at: paths.attachmentsDir); try fm.moveItem(at: paths.attRollback, to: paths.attachmentsDir)
        }
        try? fm.removeItem(at: paths.restoreMarker)
    }

    /// Called at launch: a leftover marker means the app died mid-swap, so the pre-restore data is put back.
    static func recoverInterruptedRestore(paths: StoragePaths) throws {
        if FileManager.default.fileExists(atPath: paths.restoreMarker.path) { try rollbackSwap(paths) }
    }

    // MARK: History & retention
    public static func history(in dir: URL) -> [(url: URL, info: BackupInfo?)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == BackupFormat.fileExtension }
            .map { ($0, try? inspect($0)) }
            .sorted { ($0.1?.manifest.createdAt ?? .distantPast) > ($1.1?.manifest.createdAt ?? .distantPast) }
    }

    /// Deletes the oldest backups beyond `keep`, only if the newest backup is verified.
    @discardableResult
    public static func prune(in dir: URL, keep: Int, newest: URL, password: String?) throws -> Int {
        _ = try verifyFile(newest, password: password)   // never delete old ones on an unverified new one
        let extra = history(in: dir).dropFirst(max(keep, 1))
        for e in extra where e.url != newest { try FileManager.default.removeItem(at: e.url) }
        return extra.count
    }

    static func ensureSpace(for bytes: Int, at url: URL) throws {
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, free < Int64(bytes) + 10_000_000 {
            throw BackupError.insufficientSpace
        }
    }
}

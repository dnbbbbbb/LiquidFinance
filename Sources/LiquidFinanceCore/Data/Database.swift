import Foundation
import SQLite3

/// Thin, dependency-free wrapper over the system SQLite3 library.
/// Chosen over SwiftData/Core Data because Backup/Restore needs a single, self-contained,
/// swappable .sqlite file, explicit transactions, FK enforcement and PRAGMA integrity checks.
public enum SQLValue: Equatable, Sendable {
    case int(Int64), text(String), blob(Data), null
}

public struct DBError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

public struct Row: Sendable {
    let values: [String: SQLValue]
    public func int(_ k: String) -> Int64 { if case .int(let v)? = values[k] { return v }; return 0 }
    public func text(_ k: String) -> String { if case .text(let v)? = values[k] { return v }; return "" }
    public func optInt(_ k: String) -> Int64? { if case .int(let v)? = values[k] { return v }; return nil }
    public func optText(_ k: String) -> String? { if case .text(let v)? = values[k] { return v }; return nil }
    public func bool(_ k: String) -> Bool { int(k) != 0 }
    public func uuid(_ k: String) -> UUID { UUID(uuidString: text(k)) ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) }
    public func optUUID(_ k: String) -> UUID? { optText(k).flatMap(UUID.init(uuidString:)) }
}

public protocol SQLConvertible { var sql: SQLValue { get } }
extension Int64: SQLConvertible { public var sql: SQLValue { .int(self) } }
extension Int: SQLConvertible { public var sql: SQLValue { .int(Int64(self)) } }
extension Bool: SQLConvertible { public var sql: SQLValue { .int(self ? 1 : 0) } }
extension String: SQLConvertible { public var sql: SQLValue { .text(self) } }
extension UUID: SQLConvertible { public var sql: SQLValue { .text(uuidString) } }
extension Date: SQLConvertible { public var sql: SQLValue { .int(Int64(timeIntervalSince1970)) } }
extension Data: SQLConvertible { public var sql: SQLValue { .blob(self) } }
extension Optional: SQLConvertible where Wrapped: SQLConvertible {
    public var sql: SQLValue { self?.sql ?? .null }
}

public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var depth = 0
    public let path: String

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let m = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw DBError("Cannot open database: \(m)")
        }
        try execute("PRAGMA foreign_keys = ON")
        if !readOnly { try execute("PRAGMA journal_mode = DELETE") } // single-file DB, safe to swap
        try execute("PRAGMA synchronous = FULL")
    }

    deinit { sqlite3_close(handle) }

    public func close() { lock.lock(); sqlite3_close(handle); handle = nil; lock.unlock() }

    @discardableResult
    public func execute(_ sql: String, _ params: [SQLConvertible] = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_changes(handle))
    }

    public func query(_ sql: String, _ params: [SQLConvertible] = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError() }
            var d: [String: SQLValue] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: d[name] = .int(sqlite3_column_int64(stmt, i))
                case SQLITE_TEXT: d[name] = .text(String(cString: sqlite3_column_text(stmt, i)))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, i))
                    d[name] = .blob(n == 0 ? Data() : Data(bytes: sqlite3_column_blob(stmt, i), count: n))
                default: d[name] = .null
                }
            }
            rows.append(Row(values: d))
        }
        return rows
    }

    public func scalarInt(_ sql: String, _ params: [SQLConvertible] = []) throws -> Int64 {
        try query(sql, params).first.flatMap { $0.values.values.first }.map {
            if case .int(let v) = $0 { return v }; return 0
        } ?? 0
    }

    /// Atomic unit of work. Nested calls use SAVEPOINTs. Any thrown error rolls back.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        let sp = "sp\(depth)"
        try execute(depth == 0 ? "BEGIN IMMEDIATE" : "SAVEPOINT \(sp)")
        depth += 1
        do {
            let r = try body()
            depth -= 1
            try execute(depth == 0 ? "COMMIT" : "RELEASE \(sp)")
            return r
        } catch {
            depth -= 1
            _ = try? execute(depth == 0 ? "ROLLBACK" : "ROLLBACK TO \(sp)")
            if depth > 0 { _ = try? execute("RELEASE \(sp)") }
            throw error
        }
    }

    public var userVersion: Int {
        get { Int((try? scalarInt("PRAGMA user_version")) ?? 0) }
    }
    func setUserVersion(_ v: Int) throws { try execute("PRAGMA user_version = \(v)") }

    private func prepare(_ sql: String, _ params: [SQLConvertible]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p.sql {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, transient)
            case .blob(let v): v.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), transient) }
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func lastError() -> DBError {
        DBError(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed database")
    }
}

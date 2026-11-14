import Foundation
import CryptoKit
import CommonCrypto

public struct BackupManifest: Codable, Equatable, Sendable {
    public var appName: String
    public var backupFormatVersion: Int
    public var databaseSchemaVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var accountCount: Int
    public var transactionCount: Int
    public var categoryCount: Int
    public var attachmentCount: Int
    public var totalBytes: Int64
    public var databaseSHA256: String
    public var deviceName: String
}

public struct KDFParams: Codable, Equatable, Sendable {
    public var algorithm: String   // "PBKDF2-HMAC-SHA256"
    public var iterations: Int
    public var salt: Data          // random, per backup
}

/// Plain header: needed to show restore info and to derive the key. It holds counts only, no financial rows.
/// It is bound to the ciphertext as AES-GCM additional authenticated data, so tampering is detected.
public struct BackupHeader: Codable, Equatable, Sendable {
    public var magicVersion: Int
    public var encrypted: Bool
    public var kdf: KDFParams?
    public var manifest: BackupManifest
}

public struct IntegrityFile: Codable, Equatable, Sendable {
    public var algorithm: String
    public var files: [String: String]   // entry name -> hex SHA-256
}

public enum BackupError: Error, LocalizedError, Equatable {
    case notABackup, truncated, unsupportedFormat(Int), unsupportedSchema(Int)
    case passwordRequired, wrongPasswordOrTampered, checksumMismatch(String), invalidEntryName(String)
    case missingEntry(String), manifestMismatch, databaseUnreadable(String), integrityCheckFailed(String)
    case missingAttachment(String), attachmentCorrupt(String), verificationFailed(String)
    case insufficientSpace, restoreFailedRolledBack(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup: return "Tệp không phải bản sao lưu LiquidFinance. Hãy chọn tệp .lfbackup hợp lệ."
        case .truncated: return "Tệp sao lưu bị cắt cụt hoặc hỏng. Hãy sao chép lại tệp gốc."
        case .unsupportedFormat(let v): return "Định dạng sao lưu v\(v) không được hỗ trợ. Hãy cập nhật ứng dụng."
        case .unsupportedSchema(let v): return "Bản sao lưu dùng schema v\(v) mới hơn ứng dụng. Hãy cập nhật ứng dụng."
        case .passwordRequired: return "Bản sao lưu được mã hóa. Cần nhập mật khẩu."
        case .wrongPasswordOrTampered: return "Sai mật khẩu hoặc tệp đã bị chỉnh sửa."
        case .checksumMismatch(let n): return "Checksum không khớp ở \(n). Tệp có thể đã hỏng."
        case .invalidEntryName(let n): return "Tên thành phần không hợp lệ: \(n)."
        case .missingEntry(let n): return "Thiếu thành phần bắt buộc: \(n)."
        case .manifestMismatch: return "Manifest không khớp với nội dung sao lưu."
        case .databaseUnreadable(let m): return "Không đọc được cơ sở dữ liệu trong bản sao lưu: \(m)"
        case .integrityCheckFailed(let m): return "Kiểm tra dữ liệu thất bại: \(m)"
        case .missingAttachment(let n): return "Thiếu tệp đính kèm \(n)."
        case .attachmentCorrupt(let n): return "Tệp đính kèm \(n) bị hỏng."
        case .verificationFailed(let m): return "Không thể xác minh bản sao lưu vừa tạo: \(m)"
        case .insufficientSpace: return "Không đủ dung lượng trống. Hãy giải phóng bộ nhớ rồi thử lại."
        case .restoreFailedRolledBack(let m): return "Khôi phục thất bại, dữ liệu hiện tại đã được giữ nguyên. Chi tiết: \(m)"
        }
    }
}

public enum BackupFormat {
    public static let currentFormatVersion = 1
    static let magic = Data("LFBACKUP".utf8)
    public static let fileExtension = "lfbackup"
    static let pbkdf2Iterations = 600_000

    static func sha256Hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    // MARK: inner archive  [u32 indexLen][index JSON][blobs...]
    struct IndexEntry: Codable { var name: String; var size: Int }

    static func packArchive(_ entries: [(name: String, data: Data)]) throws -> Data {
        let index = try encoder().encode(entries.map { IndexEntry(name: $0.name, size: $0.data.count) })
        var out = Data(); out.append(u32(index.count)); out.append(index)
        for e in entries { out.append(e.data) }
        return out
    }

    static func unpackArchive(_ data: Data) throws -> [String: Data] {
        guard data.count >= 4 else { throw BackupError.truncated }
        let n = Int(readU32(data, 0))
        guard data.count >= 4 + n else { throw BackupError.truncated }
        guard let index = try? decoder().decode([IndexEntry].self, from: data.subdata(in: 4..<4 + n)) else { throw BackupError.notABackup }
        var offset = 4 + n
        var result: [String: Data] = [:]
        for e in index {
            try validateEntryName(e.name)
            guard e.size >= 0, offset + e.size <= data.count else { throw BackupError.truncated }
            guard result[e.name] == nil else { throw BackupError.invalidEntryName(e.name) }
            result[e.name] = data.subdata(in: offset..<offset + e.size)
            offset += e.size
        }
        guard offset == data.count else { throw BackupError.truncated }
        return result
    }

    /// Whitelist prevents path traversal ("zip-slip") when staging files.
    static func validateEntryName(_ n: String) throws {
        if ["manifest.json", "database.sqlite", "integrity.json"].contains(n) { return }
        if n.hasPrefix("attachments/"), UUID(uuidString: String(n.dropFirst("attachments/".count))) != nil { return }
        throw BackupError.invalidEntryName(n)
    }

    // MARK: outer container  "LFBACKUP" | u32 headerLen | header JSON | payload
    static func encode(header: BackupHeader, payload: Data) throws -> Data {
        let h = try encoder().encode(header)
        var out = magic; out.append(u32(h.count)); out.append(h); out.append(payload)
        return out
    }

    static func decodeHeader(_ file: Data) throws -> (header: BackupHeader, headerBytes: Data, payload: Data) {
        guard file.count >= 12, file.prefix(8) == magic else { throw BackupError.notABackup }
        let n = Int(readU32(file, 8))
        guard n > 0, file.count >= 12 + n else { throw BackupError.truncated }
        let hb = file.subdata(in: 12..<12 + n)
        guard let h = try? decoder().decode(BackupHeader.self, from: hb) else { throw BackupError.notABackup }
        guard h.magicVersion <= currentFormatVersion else { throw BackupError.unsupportedFormat(h.magicVersion) }
        return (h, hb, file.subdata(in: 12 + n..<file.count))
    }

    // MARK: crypto (CryptoKit AES-GCM; key from password via PBKDF2 — no custom crypto)
    static func deriveKey(password: String, kdf: KDFParams) throws -> SymmetricKey {
        guard kdf.algorithm == "PBKDF2-HMAC-SHA256" else { throw BackupError.notABackup }
        var key = [UInt8](repeating: 0, count: 32)
        let pw = Array(password.utf8)
        let status = kdf.salt.withUnsafeBytes { salt in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 salt.bindMemory(to: UInt8.self).baseAddress, kdf.salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(kdf.iterations), &key, key.count)
        }
        guard status == kCCSuccess else { throw BackupError.wrongPasswordOrTampered }
        return SymmetricKey(data: key)
    }

    static func newKDF() -> KDFParams {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return KDFParams(algorithm: "PBKDF2-HMAC-SHA256", iterations: pbkdf2Iterations, salt: salt)
    }

    static func seal(_ plain: Data, key: SymmetricKey, aad: Data) throws -> Data {
        guard let c = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else { throw BackupError.truncated }
        return c
    }

    static func open(_ cipher: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: cipher), using: key, authenticating: aad) }
        catch { throw BackupError.wrongPasswordOrTampered }
    }

    static func u32(_ v: Int) -> Data { var b = UInt32(v).bigEndian; return Data(bytes: &b, count: 4) }
    static func readU32(_ d: Data, _ o: Int) -> UInt32 {
        d.subdata(in: o..<o + 4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

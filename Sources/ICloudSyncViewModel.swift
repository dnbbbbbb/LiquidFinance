import CloudKit
import Foundation
import SwiftData

@Model
final class FinanceCloudSnapshot {
    var identifier: String = "primary"
    var payload: Data = Data()
    var modifiedAt: Date = Date.now

    init(payload: Data, modifiedAt: Date = .now) {
        self.payload = payload
        self.modifiedAt = modifiedAt
    }
}

enum ICloudConnectionState: Equatable {
    case syncing, upToDate, signedOut, networkError

    var title: String {
        switch self {
        case .syncing: return "Đang đồng bộ"
        case .upToDate: return "Đã cập nhật"
        case .signedOut: return "Chưa đăng nhập iCloud"
        case .networkError: return "Lỗi mạng"
        }
    }

    var symbol: String {
        switch self {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.icloud.fill"
        case .signedOut: return "icloud.slash.fill"
        case .networkError: return "exclamationmark.icloud.fill"
        }
    }
}

@MainActor
final class ICloudSyncViewModel: ObservableObject {
    @Published private(set) var state: ICloudConnectionState = .syncing
    @Published private(set) var lastSyncedAt: Date?
    private let containerID = "iCloud.vn.liquidfinance.app"
    private let lastAppliedKey = "finance.cloud.lastAppliedAt"
    private var modelContext: ModelContext?
    private var uploadTask: Task<Void, Never>?

    init() {
        do {
            let configuration = ModelConfiguration("LiquidFinanceCloud", schema: Schema([FinanceCloudSnapshot.self]), cloudKitDatabase: .private(containerID))
            modelContext = try ModelContainer(for: FinanceCloudSnapshot.self, configurations: configuration).mainContext
        } catch {
            state = .networkError
        }
        Task { await refreshConnection() }
    }

    func refreshConnection() async {
        do {
            switch try await CKContainer(identifier: containerID).accountStatus() {
            case .available:
                state = .upToDate
            case .noAccount, .restricted:
                state = .signedOut
            case .couldNotDetermine:
                state = .networkError
            @unknown default:
                state = .networkError
            }
        } catch {
            state = .networkError
        }
    }

    func synchronize(snapshot: Data) {
        guard let modelContext, state != .signedOut else { return }
        state = .syncing
        do {
            let descriptor = FetchDescriptor<FinanceCloudSnapshot>(sortBy: [SortDescriptor(\FinanceCloudSnapshot.modifiedAt, order: .reverse)])
            if let existing = try modelContext.fetch(descriptor).first {
                existing.payload = snapshot
                existing.modifiedAt = .now
            } else {
                modelContext.insert(FinanceCloudSnapshot(payload: snapshot))
            }
            try modelContext.save()
            lastSyncedAt = .now
            UserDefaults.standard.set(lastSyncedAt, forKey: lastAppliedKey)
            state = .upToDate
        } catch {
            state = .networkError
        }
    }

    func scheduleSynchronization(snapshot: Data) {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.synchronize(snapshot: snapshot)
        }
    }

    func latestSnapshot() -> Data? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<FinanceCloudSnapshot>(sortBy: [SortDescriptor(\FinanceCloudSnapshot.modifiedAt, order: .reverse)])
        return try? modelContext.fetch(descriptor).first?.payload
    }

    func newerRemoteSnapshot() -> Data? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<FinanceCloudSnapshot>(sortBy: [SortDescriptor(\FinanceCloudSnapshot.modifiedAt, order: .reverse)])
        guard let snapshot = try? modelContext.fetch(descriptor).first else { return nil }
        let lastApplied = UserDefaults.standard.object(forKey: lastAppliedKey) as? Date ?? .distantPast
        guard snapshot.modifiedAt > lastApplied else { return nil }
        lastSyncedAt = snapshot.modifiedAt
        UserDefaults.standard.set(snapshot.modifiedAt, forKey: lastAppliedKey)
        return snapshot.payload
    }
}

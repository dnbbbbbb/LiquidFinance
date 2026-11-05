import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: FinanceStore
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingExportError = false
    @State private var showingImportPicker = false
    @State private var backupToRestore: Data?
    @State private var management: ManagementSheet?
    @State private var confirmation: Confirmation?
    @State private var reminderTime = Date()
    @State private var notificationUnavailable = false
    @AppStorage("isBalanceHidden") private var isBalanceHidden = false

    private enum ManagementSheet: String, Identifiable { case categories, wallets, recurring; var id: String { rawValue } }
    private enum Confirmation: Equatable { case reset, restore }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.1.0"
    }

    private struct CurrencyOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    private let currencies = [
        CurrencyOption(code: "VND", name: "Việt Nam đồng"),
        CurrencyOption(code: "USD", name: "Đô la Mỹ"),
        CurrencyOption(code: "EUR", name: "Euro"),
        CurrencyOption(code: "JPY", name: "Yên Nhật"),
        CurrencyOption(code: "GBP", name: "Bảng Anh")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                preferencesSection
                managementSection
                recurringSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 110)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
        .onAppear {
            reminderTime = Calendar.current.date(bySettingHour: store.preferences.reminderHour, minute: store.preferences.reminderMinute, second: 0, of: .now) ?? .now
            if store.preferences.reminderEnabled { scheduleReminder(true) }
            if store.preferences.budgetAlertsEnabled { configureBudgetAlerts(true) }
        }
        .onChange(of: reminderTime) { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            store.updatePreferences { $0.reminderHour = parts.hour ?? 20; $0.reminderMinute = parts.minute ?? 0 }
            if store.preferences.reminderEnabled { scheduleReminder(true) }
        }
        .onAppear { store.syncBalanceVisibility(isBalanceHidden) }
        .onChange(of: isBalanceHidden) { store.syncBalanceVisibility($0) }
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $management) { item in
            switch item {
            case .categories: CategoryManagementView(store: store)
            case .wallets: WalletManagementView(store: store)
            case .recurring: RecurringManagementView(store: store)
            }
        }
        .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                backupToRestore = try Data(contentsOf: url)
                confirmation = .restore
            } catch { showingExportError = true }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if confirmation == .restore {
                Button("Thay thế dữ liệu hiện tại", role: .destructive) {
                    guard let backupToRestore else { return }
                    do {
                        try store.restoreBackup(backupToRestore)
                    } catch { showingExportError = true }
                    self.backupToRestore = nil
                    confirmation = nil
                }
                Button("Hủy", role: .cancel) { backupToRestore = nil; confirmation = nil }
            } else if confirmation == .reset {
                Button("Xóa toàn bộ dữ liệu", role: .destructive) {
                    store.clearAllData()
                    confirmation = nil
                }
                Button("Hủy", role: .cancel) { confirmation = nil }
            }
        } message: {
            Text(confirmation == .restore ? "Dữ liệu hiện tại sẽ được thay thế bằng nội dung trong tệp sao lưu." : "Tất cả giao dịch, ngân sách và cài đặt trên iPhone này sẽ bị xóa.")
        }
        .alert("Không thể xử lý tệp", isPresented: $showingExportError) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text("Kiểm tra tệp sao lưu rồi thử lại.")
        }
        .alert("Không thể bật thông báo", isPresented: $notificationUnavailable) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text("Hãy cho phép thông báo trong Cài đặt iPhone để nhận nhắc nhở và cảnh báo ngân sách.")
        }
    }

    private var confirmationTitle: String {
        confirmation == .restore ? "Khôi phục bản sao lưu?" : "Xóa toàn bộ dữ liệu?"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CÁ NHÂN HÓA TRẢI NGHIỆM")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FinanceStyle.purple)
            Text("Cài đặt")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Tùy chỉnh cách bạn theo dõi tài chính.")
                .font(.system(size: 14))
                .foregroundStyle(FinanceStyle.muted)
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Tùy chọn", systemImage: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
                .padding(.bottom, 12)
            HStack {
                Label("Đơn vị tiền", systemImage: "dollarsign.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FinanceStyle.ink)
                Spacer()
                Picker("Đơn vị tiền", selection: Binding(
                    get: { store.preferences.currencyCode },
                    set: { value in store.updatePreferences { $0.currencyCode = value } }
                )) {
                    ForEach(currencies) { currency in
                        Text("\(currency.code) · \(currency.name)").tag(currency.code)
                    }
                }
                .labelsHidden()
                .tint(FinanceStyle.purple)
                .fixedSize()
            }
            Divider().overlay(FinanceStyle.line).padding(.vertical, 8)
            HStack {
                Label("Giao diện", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(FinanceStyle.ink)
                Spacer()
                Picker("Giao diện", selection: Binding(
                    get: { store.preferences.appearance },
                    set: { value in store.updatePreferences { $0.appearance = value } }
                )) {
                    Text("Tự động").tag("system")
                    Text("Sáng").tag("light")
                    Text("Tối").tag("dark")
                }
                .labelsHidden().tint(FinanceStyle.purple).fixedSize()
            }
            Divider().overlay(FinanceStyle.line).padding(.vertical, 8)
            Toggle(isOn: $isBalanceHidden) {
                Label("Ẩn số dư trên màn hình", systemImage: "eye.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FinanceStyle.ink)
            }
            .tint(FinanceStyle.purple)
            Divider().overlay(FinanceStyle.line).padding(.vertical, 8)
            Toggle("Nhắc nhập liệu cuối ngày", isOn: Binding(
                get: { store.preferences.reminderEnabled },
                set: { value in
                    store.updatePreferences { $0.reminderEnabled = value }
                    scheduleReminder(value)
                }
            )).tint(FinanceStyle.purple)
            if store.preferences.reminderEnabled {
                DatePicker("Thông báo lúc", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
            }
            if notificationUnavailable {
                Text("Hãy cho phép thông báo trong Cài đặt iPhone để nhận nhắc nhở.")
                    .font(.system(size: 12)).foregroundStyle(FinanceStyle.red)
            }
            Divider().overlay(FinanceStyle.line).padding(.vertical, 8)
            Toggle("Cảnh báo khi gần hết ngân sách", isOn: Binding(
                get: { store.preferences.budgetAlertsEnabled },
                set: { value in
                    store.updatePreferences { $0.budgetAlertsEnabled = value }
                    configureBudgetAlerts(value)
                }
            ))
            .tint(FinanceStyle.purple)
            Text("Thông báo khi đã dùng 80%, đạt giới hạn hoặc vượt ngân sách.")
                .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("Đổi đơn vị tiền không quy đổi các số tiền đã nhập.")
                .font(.system(size: 11))
                .foregroundStyle(FinanceStyle.muted)
                .padding(.leading, 17)
                .offset(y: 23)
        }
        .padding(.bottom, 22)
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quản lý", systemImage: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(FinanceStyle.ink)
            Button { management = .categories } label: {
                settingsActionRow(icon: "square.grid.2x2", title: "Danh mục cha và con", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { management = .wallets } label: {
                settingsActionRow(icon: "wallet.bifold", title: "Ví và nguồn tiền", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Định kỳ", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(FinanceStyle.ink)
            Button { management = .recurring } label: {
                settingsActionRow(icon: "arrow.clockwise", title: "Giao dịch định kỳ", color: FinanceStyle.purple)
            }
            .buttonStyle(.plain)
            Text("Lặp theo ngày, ngày làm việc, tuần, 2 tuần, tháng, quý hoặc năm.")
                .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dữ liệu của bạn", systemImage: "externaldrive")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
            Button(action: exportCSV) {
                settingsActionRow(icon: "square.and.arrow.up", title: "Xuất giao dịch dạng CSV", color: FinanceStyle.purple)
            }
            .buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button(action: exportBackup) {
                settingsActionRow(icon: "externaldrive.badge.checkmark", title: "Sao lưu toàn bộ dữ liệu (JSON)", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { showingImportPicker = true } label: {
                settingsActionRow(icon: "square.and.arrow.down", title: "Nhập bản sao lưu JSON", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Toggle(isOn: Binding(get: { store.iCloudSyncEnabled }, set: { store.setICloudSyncEnabled($0) })) {
                Label("Sao lưu và đồng bộ iCloud", systemImage: "icloud.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceStyle.purple)
            }
            .tint(FinanceStyle.purple)
            HStack {
                Image(systemName: iCloudStatusIcon)
                    .foregroundStyle(iCloudStatusColor)
                Text(store.iCloudStatus)
                Spacer()
                if store.iCloudSyncEnabled {
                    Button("Đồng bộ ngay") { Task { await store.syncWithICloud() } }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FinanceStyle.purple)
                }
            }
            .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
            if let lastSync = store.lastICloudSyncDate {
                Text("Cập nhật lần cuối: \(DateText.dateTime(lastSync))")
                    .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
            }
            Text("Tự động đồng bộ hai chiều qua Apple ID khi bạn bật iCloud. Bạn vẫn có thể xuất hoặc nhập JSON nếu không dùng iCloud Drive.")
                .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
            Divider().overlay(FinanceStyle.line)
            Button { confirmation = .reset } label: {
                settingsActionRow(icon: "trash", title: "Xóa toàn bộ dữ liệu", color: FinanceStyle.red)
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iCloudStatusIcon: String {
        switch store.iCloudStatus {
        case "Đang đồng bộ": return "arrow.triangle.2.circlepath.icloud"
        case "Đã cập nhật": return "checkmark.icloud.fill"
        case "Chưa đăng nhập iCloud": return "icloud.slash"
        default: return "exclamationmark.icloud.fill"
        }
    }

    private var iCloudStatusColor: Color {
        switch store.iCloudStatus {
        case "Đã cập nhật": return FinanceStyle.green
        case "Lỗi mạng", "Chưa đăng nhập iCloud": return FinanceStyle.red
        default: return FinanceStyle.purple
        }
    }

    private func settingsActionRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(FinanceStyle.muted)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var aboutSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(FinanceStyle.green)
            Text("LiquidFinance")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Đơn giản, riêng tư, dành cho bạn · Phiên bản \(appVersion)")
                .font(.system(size: 12))
                .foregroundStyle(FinanceStyle.muted)
            Text("Dữ liệu lưu trên thiết bị; bạn có thể bật iCloud để sao lưu và đồng bộ an toàn giữa các thiết bị.")
                .font(.system(size: 12))
                .foregroundStyle(FinanceStyle.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func scheduleReminder(_ enabled: Bool) {
        let hour = store.preferences.reminderHour
        let minute = store.preferences.reminderMinute
        Task {
            let success = await DailyReminder.configure(enabled: enabled, hour: hour, minute: minute)
            await MainActor.run {
                notificationUnavailable = enabled && !success
                if enabled && !success { store.updatePreferences { $0.reminderEnabled = false } }
            }
        }
    }

    private func configureBudgetAlerts(_ enabled: Bool) {
        Task {
            let success = await BudgetAlertNotification.configure(enabled: enabled)
            await MainActor.run {
                notificationUnavailable = enabled && !success
                if enabled && !success { store.updatePreferences { $0.budgetAlertsEnabled = false } }
            }
        }
    }

    private func exportCSV() {
        guard let url = CSVExporter.createFile(transactions: store.transactions) else {
            showingExportError = true
            return
        }
        exportURL = url
        showingShareSheet = true
    }

    private func exportBackup() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidFinance-Backup-\(Int(Date().timeIntervalSince1970)).json")
            try store.backupData().write(to: url, options: .atomic)
            exportURL = url
            showingShareSheet = true
        } catch { showingExportError = true }
    }
}

private enum CSVExporter {
    static func createFile(transactions: [FinanceTransaction]) -> URL? {
        let header = ["Ngày", "Loại", "Tên", "Danh mục", "Số tiền", "Ví", "Ghi chú"]
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                ISO8601DateFormatter().string(from: transaction.date),
                transaction.type.title,
                transaction.title,
                transaction.category.rawValue,
                String(transaction.amount),
                transaction.account,
                transaction.note
            ]
        }
        let csv = ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidFinance-GiaoDich.csv")
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}


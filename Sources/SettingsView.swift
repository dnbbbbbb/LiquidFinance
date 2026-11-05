import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: FinanceStore
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingArchiveError = false
    @State private var showingImportPicker = false
    @State private var archiveToImport: Data?
    @State private var importIntent: ImportIntent = .data
    @State private var archiveErrorMessage = ""
    @State private var importResultMessage = ""
    @State private var showingImportResult = false
    @State private var management: ManagementSheet?
    @State private var confirmation: Confirmation?
    @State private var reminderTime = Date()
    @State private var notificationUnavailable = false
    @AppStorage("isBalanceHidden") private var isBalanceHidden = false

    private enum ManagementSheet: String, Identifiable { case categories, wallets, recurring; var id: String { rawValue } }
    private enum Confirmation: Equatable { case reset, importData, restoreBackup }
    private enum ImportIntent { case data, backup }

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
        .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: importIntent == .data ? [LiquidFinanceArchiveType.data] : [LiquidFinanceArchiveType.backup], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                archiveToImport = try Data(contentsOf: url)
                confirmation = importIntent == .data ? .importData : .restoreBackup
            } catch { presentArchiveError(error) }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if confirmation == .importData {
                Button("Nhập và gộp dữ liệu") { importData() }
                Button("Hủy", role: .cancel) { archiveToImport = nil; confirmation = nil }
            } else if confirmation == .restoreBackup {
                Button("Thay thế dữ liệu hiện tại", role: .destructive) {
                    restoreBackup()
                }
                Button("Hủy", role: .cancel) { archiveToImport = nil; confirmation = nil }
            } else if confirmation == .reset {
                Button("Xóa toàn bộ dữ liệu", role: .destructive) {
                    store.clearAllData()
                    confirmation = nil
                }
                Button("Hủy", role: .cancel) { confirmation = nil }
            }
        } message: {
            Text(confirmation == .importData ? "Các giao dịch, danh mục và ví mới sẽ được thêm vào. Dữ liệu đang có sẽ không bị thay thế." : (confirmation == .restoreBackup ? "Dữ liệu hiện tại sẽ được thay thế bằng nội dung trong tệp sao lưu." : "Tất cả giao dịch, ngân sách và cài đặt trên iPhone này sẽ bị xóa."))
        }
        .alert("Không thể xử lý tệp", isPresented: $showingArchiveError) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text(archiveErrorMessage)
        }
        .alert("Đã nhập dữ liệu", isPresented: $showingImportResult) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text(importResultMessage)
        }
        .alert("Không thể bật thông báo", isPresented: $notificationUnavailable) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text("Hãy cho phép thông báo trong Cài đặt iPhone để nhận nhắc nhở và cảnh báo ngân sách.")
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .importData: return "Nhập dữ liệu LiquidFinance?"
        case .restoreBackup: return "Khôi phục bản sao lưu?"
        default: return "Xóa toàn bộ dữ liệu?"
        }
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
            Label("Trung tâm dữ liệu LiquidFinance", systemImage: "externaldrive")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
            Text("Chỉ dùng tệp LiquidFinance để dữ liệu của bạn luôn nhất quán và an toàn khi chuyển thiết bị.")
                .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
            Button(action: exportData) {
                settingsActionRow(icon: "square.and.arrow.up", title: "Xuất dữ liệu", detail: ".liquidfinance-data", color: FinanceStyle.purple)
            }
            .buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { beginImport(.data) } label: {
                settingsActionRow(icon: "square.and.arrow.down", title: "Nhập dữ liệu", detail: "Gộp giao dịch mới", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button(action: exportBackup) {
                settingsActionRow(icon: "externaldrive.badge.checkmark", title: "Tạo bản sao lưu", detail: ".liquidfinance-backup", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { beginImport(.backup) } label: {
                settingsActionRow(icon: "arrow.counterclockwise", title: "Khôi phục bản sao lưu", detail: "Thay thế toàn bộ dữ liệu", color: FinanceStyle.purple)
            }.buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { confirmation = .reset } label: {
                settingsActionRow(icon: "trash", title: "Xóa toàn bộ dữ liệu", color: FinanceStyle.red)
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func settingsActionRow(icon: String, title: String, detail: String? = nil, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(FinanceStyle.muted) }
            }
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
            Text("Dữ liệu lưu trên thiết bị. Dùng tệp LiquidFinance để xuất, nhập và sao lưu an toàn.")
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

    private func beginImport(_ intent: ImportIntent) {
        importIntent = intent
        showingImportPicker = true
    }

    private func exportData() {
        do {
            shareArchive(data: try store.exportData(), filename: "LiquidFinance-Data-\(archiveTimestamp()).liquidfinance-data")
        } catch { presentArchiveError(error) }
    }

    private func exportBackup() {
        do {
            shareArchive(data: try store.createBackup(), filename: "LiquidFinance-Backup-\(archiveTimestamp()).liquidfinance-backup")
        } catch { presentArchiveError(error) }
    }

    private func importData() {
        defer { archiveToImport = nil; confirmation = nil }
        do {
            guard let archiveToImport else { return }
            let count = try store.importData(archiveToImport)
            importResultMessage = count == 0 ? "Không có giao dịch mới để nhập." : "Đã thêm \(count) giao dịch mới."
            showingImportResult = true
        } catch { presentArchiveError(error) }
    }

    private func restoreBackup() {
        defer { archiveToImport = nil; confirmation = nil }
        do {
            guard let archiveToImport else { return }
            try store.restoreBackup(archiveToImport)
            importResultMessage = "Toàn bộ dữ liệu LiquidFinance đã được khôi phục."
            showingImportResult = true
        } catch { presentArchiveError(error) }
    }

    private func shareArchive(data: Data, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            showingShareSheet = true
        } catch { presentArchiveError(error) }
    }

    private func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    private func presentArchiveError(_ error: Error) {
        archiveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Không thể đọc hoặc tạo tệp LiquidFinance. Hãy thử lại."
        showingArchiveError = true
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}


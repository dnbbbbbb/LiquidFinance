import SwiftUI
import UniformTypeIdentifiers
import LiquidFinanceCore

@main struct LiquidFinanceApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var theme = ThemeEngine()
    @Environment(\.colorScheme) private var scheme
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(env).environmentObject(theme)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.palette.accent)
                .onAppear { theme.load(env.settings); theme.systemIsDark = scheme == .dark }
                .onChange(of: scheme) { theme.systemIsDark = $0 == .dark }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var theme: ThemeEngine
    @State private var showAdd = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                DashboardView().tabItem { Label("Trang chủ", systemImage: "house") }
                TransactionsView().tabItem { Label("Giao dịch", systemImage: "list.bullet") }
                NotImplementedView(title: "Ngân sách", detail: "Bảng budgets đã có trong schema; logic và giao diện chưa được triển khai.")
                    .tabItem { Label("Ngân sách", systemImage: "chart.pie") }
                NotImplementedView(title: "Phân tích", detail: "Đã có totals/expenseByCategory trong LedgerService; biểu đồ Swift Charts chưa được triển khai.")
                    .tabItem { Label("Phân tích", systemImage: "chart.xyaxis.line") }
                SettingsView().tabItem { Label("Cài đặt", systemImage: "gearshape") }
            }
            Button { showAdd = true } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 58, height: 58)
            }
            .floatingGlass(in: Circle()).padding(.trailing, 20).padding(.bottom, 70)
            .accessibilityLabel("Thêm giao dịch")
        }
        .sheet(isPresented: $showAdd) { AddTransactionView().environmentObject(env).environmentObject(theme) }
    }
}

struct NotImplementedView: View {
    let title: String, detail: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Chưa triển khai. " + detail))
    }
}

struct DashboardView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var theme: ThemeEngine
    @State private var total = Money(0); @State private var totals = PeriodTotals(income: Money(0), expense: Money(0))
    @State private var recent: [FinanceTransaction] = []
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tổng số dư").font(.subheadline).foregroundStyle(theme.palette.secondaryText)
                        Text(total.formatted()).font(.system(size: 40, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    }
                    HStack {
                        stat("Thu tháng này", totals.income, theme.palette.income)
                        stat("Chi tháng này", totals.expense, theme.palette.expense)
                    }
                    Text("Tỷ lệ tiết kiệm: \(totals.savingsRatePercent)%").font(.footnote).foregroundStyle(theme.palette.secondaryText)
                    Text("Giao dịch gần đây").font(.headline)
                    if recent.isEmpty { Text("Chưa có giao dịch. Nhấn + để thêm.").foregroundStyle(theme.palette.secondaryText) }
                    ForEach(recent) { TransactionRow(tx: $0) }
                }.padding()
            }
            .background(theme.palette.background)
            .navigationTitle("LiquidFinance")
            .task(id: env.revision) { load() }
        }
    }
    func stat(_ t: String, _ m: Money, _ c: Color) -> some View {
        VStack(alignment: .leading) { Text(t).font(.caption).foregroundStyle(theme.palette.secondaryText)
            Text(m.formatted()).font(.headline).foregroundStyle(c).minimumScaleFactor(0.6).lineLimit(1) }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    func load() {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: Date())!
        total = (try? env.ledger.totalBalance()) ?? Money(0)
        totals = (try? env.ledger.totals(from: start.start, to: start.end)) ?? totals
        recent = (try? env.ledger.page(TransactionQuery(), limit: 5)) ?? []
    }
}

struct TransactionRow: View {
    @EnvironmentObject var theme: ThemeEngine
    let tx: FinanceTransaction
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(tx.title.isEmpty ? tx.type.rawValue.capitalized : tx.title).font(.body)
                Text(tx.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(theme.palette.secondaryText)
            }
            Spacer()
            Text(sign + tx.amount.formatted()).font(.body.monospacedDigit().bold()).foregroundStyle(color)
        }
    }
    var sign: String { tx.type == .income || tx.type == .refund ? "+" : (tx.type == .expense ? "−" : "") }
    var color: Color { tx.type == .income || tx.type == .refund ? theme.palette.income : (tx.type == .expense ? theme.palette.expense : theme.palette.secondaryText) }
}

struct TransactionsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var items: [FinanceTransaction] = []
    @State private var query = TransactionQuery(); @State private var search = ""
    @State private var exhausted = false; @State private var error: String?
    private let pageSize = 50
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(items) { tx in
                    TransactionRow(tx: tx)
                        .swipeActions { Button("Xóa", role: .destructive) { delete(tx) }
                            Button("Nhân bản") { try? env.ledger.duplicate(tx.id); env.revision += 1 }.tint(.blue) }
                        .onAppear { if tx.id == items.last?.id { loadMore() } }
                }
            }
            .overlay { if items.isEmpty && error == nil { ContentUnavailableView(search.isEmpty ? "Chưa có giao dịch" : "Không tìm thấy", systemImage: "tray") } }
            .searchable(text: $search)
            .navigationTitle("Giao dịch")
            .task(id: env.revision) { reload() }
            .onChange(of: search) { query.search = $0; reload() }
        }
    }
    func reload() { exhausted = false; items = []; loadMore() }
    func loadMore() {
        guard !exhausted else { return }
        do { let p = try env.ledger.page(query, limit: pageSize, offset: items.count); items += p; exhausted = p.count < pageSize }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ tx: FinanceTransaction) {
        do { try env.ledger.delete(tx.id); env.revision += 1 } catch { self.error = error.localizedDescription }
    }
}

struct AddTransactionView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) var dismiss
    @State private var type: TransactionType = .expense
    @State private var amountText = ""; @State private var note = ""; @State private var date = Date()
    @State private var accounts: [Account] = []; @State private var categories: [Category] = []
    @State private var accountId: UUID?; @State private var toAccountId: UUID?; @State private var categoryId: UUID?
    @State private var fee = ""; @State private var error: String?
    /// One key per sheet presentation: tapping Save twice can never create two rows.
    @State private var intentKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Picker("Loại", selection: $type) { Text("Chi").tag(TransactionType.expense); Text("Thu").tag(TransactionType.income); Text("Chuyển").tag(TransactionType.transfer) }
                    .pickerStyle(.segmented)
                Section("Số tiền") {
                    TextField("0", text: $amountText).keyboardType(.numberPad).font(.title.bold())
                    if let m = Money.parse(amountText) { Text(m.formatted()).foregroundStyle(.secondary) }
                }
                Section {
                    Picker(type == .transfer ? "Từ tài khoản" : "Tài khoản", selection: $accountId) { ForEach(accounts) { Text($0.name).tag(Optional($0.id)) } }
                    if type == .transfer {
                        Picker("Đến tài khoản", selection: $toAccountId) { Text("Chọn").tag(UUID?.none); ForEach(accounts) { Text($0.name).tag(Optional($0.id)) } }
                        TextField("Phí chuyển khoản", text: $fee).keyboardType(.numberPad)
                    } else {
                        Picker("Danh mục", selection: $categoryId) {
                            Text("Chưa phân loại").tag(UUID?.none)
                            ForEach(categories.filter { $0.parentId != nil && $0.kind == (type == .income ? .income : .expense) }) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    DatePicker("Ngày", selection: $date)
                    TextField("Ghi chú", text: $note)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Thêm giao dịch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
            .task {
                accounts = (try? env.ledger.accounts()) ?? []; categories = (try? env.ledger.categories()) ?? []
                accountId = (try? env.settings.get(SettingsStore.Key.lastUsedAccount)).flatMap { $0 }.flatMap(UUID.init(uuidString:)) ?? accounts.first?.id
            }
            .onChange(of: type) { _ in categoryId = nil }
        }
    }
    func save() {
        guard let amount = Money.parse(amountText), let accountId else { error = LedgerError.invalidAmount.localizedDescription; return }
        let tx = FinanceTransaction(type: type, amount: amount, accountId: accountId, toAccountId: type == .transfer ? toAccountId : nil,
                                    fee: type == .transfer ? (Money.parse(fee) ?? Money(0)) : Money(0), categoryId: type == .transfer ? nil : categoryId,
                                    date: date, note: note, idempotencyKey: intentKey)
        do { try env.ledger.add(tx); try? env.settings.set(SettingsStore.Key.lastUsedAccount, accountId.uuidString); env.revision += 1; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var theme: ThemeEngine
    @State private var iconError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Cá nhân hóa") {
                    Picker("Giao diện", selection: Binding(get: { theme.theme }, set: { theme.set($0, store: env.settings) })) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Biểu tượng ứng dụng", selection: Binding(get: { AppIconChoice(rawValue: (try? env.settings.get(SettingsStore.Key.appIcon)) ?? "") ?? .default }, set: { c in
                        Task { do { try await c.apply(); try? env.settings.set(SettingsStore.Key.appIcon, c.rawValue) } catch { iconError = error.localizedDescription } }
                    })) { ForEach(AppIconChoice.allCases) { Text($0.title).tag($0) } }
                    if let iconError { Text(iconError).foregroundStyle(.red).font(.caption) }
                }
                Section("Dữ liệu & sao lưu") { NavigationLink("Trung tâm sao lưu") { BackupCenterView() } }
                Section("Chưa triển khai") {
                    Text("Tài khoản, Danh mục, Giao dịch định kỳ, Khóa ứng dụng/Face ID, Thông báo, Ngôn ngữ/Tiền tệ").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Cài đặt")
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url) }
}

struct BackupCenterView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var password = ""; @State private var busy = false; @State private var progress = 0.0; @State private var stage = ""
    @State private var message: String?; @State private var history: [(url: URL, info: BackupInfo?)] = []
    @State private var exporting: BackupDocument?; @State private var importing = false
    @State private var pending: URL?; @State private var prepared: PreparedBackup?; @State private var restorePassword = ""
    @State private var confirm = false; @State private var needPassword = false

    var body: some View {
        Form {
            Section("Sao lưu") {
                SecureField("Mật khẩu mã hóa (tùy chọn)", text: $password)
                Button("Sao lưu ngay") { backup() }.disabled(busy)
                if busy { ProgressView(value: progress) { Text(stage) } }
                if let message { Text(message).font(.footnote) }
            }
            Section("Khôi phục") { Button("Chọn tệp .lfbackup…") { importing = true }.disabled(busy) }
            Section("Lịch sử") {
                if history.isEmpty { Text("Chưa có bản sao lưu").foregroundStyle(.secondary) }
                ForEach(history, id: \.url) { h in
                    VStack(alignment: .leading) {
                        Text(h.url.lastPathComponent).font(.footnote)
                        if let i = h.info { Text("\(i.manifest.transactionCount) giao dịch · \(ByteCountFormatter.string(fromByteCount: i.fileSize, countStyle: .file))\(i.isEncrypted ? " · mã hóa" : "")").font(.caption).foregroundStyle(.secondary) }
                        else { Text("Không hợp lệ").font(.caption).foregroundStyle(.red) }
                    }
                    .swipeActions { Button("Chia sẻ") { exporting = BackupDocument(url: h.url) } }
                }
            }
        }
        .navigationTitle("Trung tâm sao lưu")
        .task { history = BackupService.history(in: env.appDB.paths.backupsDir) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { r in
            if case .success(let u) = r { inspect(u) }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }), document: exporting, contentType: .data,
                      defaultFilename: BackupService.defaultFileName()) { _ in exporting = nil }
        .alert("Nhập mật khẩu", isPresented: $needPassword) {
            SecureField("Mật khẩu", text: $restorePassword)
            Button("Tiếp tục") { if let pending { prepare(pending) } }; Button("Hủy", role: .cancel) {}
        }
        .confirmationDialog("Thay thế TOÀN BỘ dữ liệu hiện tại?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Khôi phục", role: .destructive) { restore() }
            Button("Hủy", role: .cancel) { if let prepared { BackupService.discard(prepared) } }
        } message: {
            if let i = prepared?.info.manifest {
                Text("\(i.accountCount) tài khoản · \(i.transactionCount) giao dịch · \(i.categoryCount) danh mục · tạo \(i.createdAt.formatted()). Một bản sao lưu dự phòng sẽ được tạo trước.")
            }
        }
    }

    func run(_ work: @escaping @Sendable (@escaping BackupProgress) throws -> String) {
        busy = true; message = nil
        let report: BackupProgress = { p, s in Task { @MainActor in progress = p; stage = s } }
        Task.detached {   // off the main thread
            do { let m = try work(report); await MainActor.run { message = m; busy = false; history = BackupService.history(in: env.appDB.paths.backupsDir) } }
            catch { await MainActor.run { message = error.localizedDescription; busy = false } }
        }
    }

    func backup() {
        let dir = env.appDB.paths.backupsDir.appendingPathComponent(BackupService.defaultFileName()); let pw = password.isEmpty ? nil : password
        let app = env.appDB
        run { rep in
            let info = try BackupService.createBackup(from: app, to: dir, password: pw, progress: rep)
            return "Đã sao lưu và xác minh: \(info.manifest.transactionCount) giao dịch."
        }
    }
    func inspect(_ u: URL) {
        let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
        let local = env.appDB.paths.stagingDir.appendingPathComponent("import.lfbackup")
        do {
            try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: local); try FileManager.default.copyItem(at: u, to: local)
            let info = try BackupService.inspect(local); pending = local
            if info.isEncrypted { needPassword = true } else { prepare(local) }
        } catch { message = error.localizedDescription }
    }
    func prepare(_ url: URL) {
        let pw = restorePassword.isEmpty ? nil : restorePassword; let paths = env.appDB.paths
        busy = true
        Task.detached {
            do { let p = try BackupService.prepareRestore(from: url, password: pw, paths: paths)
                 await MainActor.run { prepared = p; busy = false; confirm = true } }
            catch { await MainActor.run { message = error.localizedDescription; busy = false } }
        }
    }
    func restore() {
        guard let p = prepared else { return }
        let app = env.appDB
        run { rep in try BackupService.restoreFull(p, into: app, progress: rep); await_reload(); return "Khôi phục thành công." }
    }
    func await_reload() { Task { @MainActor in env.reloadServices() } }
}

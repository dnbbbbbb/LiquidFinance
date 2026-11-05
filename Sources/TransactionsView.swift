import SwiftUI

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case expense = "Chi tiêu"
    case income = "Thu nhập"
    var id: String { rawValue }
}

enum TransactionEntryMode: String, CaseIterable, Identifiable {
    case expense, income, transfer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: return "Chi tiêu"
        case .income: return "Thu nhập"
        case .transfer: return "Chuyển khoản"
        }
    }
    var transactionType: TransactionType { self == .income ? .income : .expense }
}

struct TransactionsView: View {
    @ObservedObject var store: FinanceStore
    @State private var searchText = ""
    @State private var filter: TransactionFilter = .all
    @State private var timeFilterEnabled = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var rangeEnd = Date.now
    @State private var selectedMonth = Date.now
    @State private var editingTransaction: FinanceTransaction?

    private var filteredTransactions: [FinanceTransaction] {
        store.transactions
            .filter { transaction in
                (filter == .all || (filter == .expense && transaction.type == .expense) || (filter == .income && transaction.type == .income))
                    && (!timeFilterEnabled || (transaction.date >= min(rangeStart, rangeEnd) && transaction.date <= max(rangeStart, rangeEnd)))
                    && (searchText.isEmpty || transaction.title.localizedCaseInsensitiveContains(searchText)
                        || transaction.category.rawValue.localizedCaseInsensitiveContains(searchText)
                        || transaction.note.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                searchField
                filterPicker
                MonthNavigator(month: $selectedMonth)
                DateRangeFilterView(isEnabled: $timeFilterEnabled, start: $rangeStart, end: $rangeEnd)

                if filteredTransactions.isEmpty {
                    EmptyState(
                        symbol: searchText.isEmpty ? "arrow.left.arrow.right" : "magnifyingglass",
                        title: searchText.isEmpty ? "Chưa có giao dịch" : "Không tìm thấy kết quả",
                        message: searchText.isEmpty ? "Nhấn nút + để thêm thu nhập hoặc chi tiêu." : "Thử từ khóa khác hoặc bỏ bộ lọc hiện tại."
                    )
                    .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredTransactions.enumerated()), id: \.element.id) { index, transaction in
                            Button { editingTransaction = transaction } label: {
                                TransactionRow(transaction: transaction, currencyCode: store.preferences.currencyCode)
                                    .padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteTransaction(id: transaction.id)
                                } label: {
                                    Label("Xóa giao dịch", systemImage: "trash")
                                }
                            }
                            if index < filteredTransactions.count - 1 {
                                Divider().overlay(FinanceStyle.line).padding(.leading, 70)
                            }
                        }
                    }
                    .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 110)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditorView(store: store, transaction: transaction)
        }
        .onChange(of: selectedMonth) { month in
            let start = FinanceDate.startOfMonth(containing: month)
            rangeStart = start
            rangeEnd = Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? month
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DÒNG TIỀN CỦA BẠN")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FinanceStyle.purple)
            Text("Giao dịch")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("\(filteredTransactions.count) khoản được tìm thấy")
                .font(.system(size: 14))
                .foregroundStyle(FinanceStyle.muted)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(FinanceStyle.muted)
            TextField("Tìm theo tên, danh mục...", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(FinanceStyle.muted)
                }
                .accessibilityLabel("Xóa tìm kiếm")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(TransactionFilter.allCases) { option in
                Button { filter = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(filter == option ? .white : FinanceStyle.muted)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(filter == option ? FinanceStyle.purple : FinanceStyle.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TransactionEditorView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let transaction: FinanceTransaction?

    @State private var mode: TransactionEntryMode
    @State private var type: TransactionType
    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var category: FinanceCategory
    @State private var walletID: UUID
    @State private var destinationWalletID: UUID
    @State private var transferFeeText: String
    @State private var note: String
    @State private var includeInReports: Bool
    @State private var usesCategoryAsTitle: Bool
    @State private var isRecurring: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var recurrenceWeekday: Int
    @State private var showingValidationError = false
    @State private var showingCategoryPicker = false

    init(store: FinanceStore, transaction: FinanceTransaction? = nil, initialMode: TransactionEntryMode = .expense) {
        self.store = store
        self.transaction = transaction
        let entryMode: TransactionEntryMode
        if transaction?.isInternalTransfer == true { entryMode = .transfer }
        else if let transaction { entryMode = transaction.type == .income ? .income : .expense }
        else { entryMode = initialMode }
        _mode = State(initialValue: entryMode)
        _type = State(initialValue: entryMode.transactionType)
        _title = State(initialValue: transaction?.title ?? "")
        _amountText = State(initialValue: transaction.map { $0.amount == 0 ? "" : AmountInput.format($0.amount) } ?? "")
        _date = State(initialValue: transaction?.date ?? .now)
        _category = State(initialValue: transaction?.category ?? .food)
        let transferSource = transaction.flatMap { item -> FinanceTransaction? in
            guard item.isInternalTransfer, let transferID = item.transferID else { return nil }
            return store.transactions.first { $0.transferID == transferID && $0.isInternalTransfer && $0.type == .expense }
        }
        let transferDestination = transaction.flatMap { item -> FinanceTransaction? in
            guard item.isInternalTransfer, let transferID = item.transferID else { return nil }
            return store.transactions.first { $0.transferID == transferID && $0.isInternalTransfer && $0.type == .income }
        }
        let existingWallet = store.wallets.first(where: { $0.id == (transferSource?.walletID ?? transaction?.walletID) }) ?? store.wallets.first(where: { $0.name == (transferSource?.account ?? transaction?.account) })
        let selectedWalletID = existingWallet?.id ?? store.mostRecentlyUsedWallet.id
        _walletID = State(initialValue: selectedWalletID)
        _destinationWalletID = State(initialValue: transferDestination?.walletID ?? store.wallets.first(where: { $0.id != selectedWalletID })?.id ?? selectedWalletID)
        let transferFee = transaction.flatMap { item -> FinanceTransaction? in
            guard let transferID = item.transferID else { return nil }
            return store.transactions.first { $0.transferID == transferID && !$0.isInternalTransfer && $0.category.id == FinanceCategory.transferFee.id }
        }
        _transferFeeText = State(initialValue: transferFee.map { AmountInput.format($0.amount) } ?? "")
        _note = State(initialValue: transaction?.note ?? "")
        _includeInReports = State(initialValue: transaction?.includeInReports ?? true)
        _usesCategoryAsTitle = State(initialValue: transaction.map { $0.title == $0.category.name } ?? true)
        let existingRule = store.recurringRules.first(where: { $0.id == transaction?.recurrenceID })
        _isRecurring = State(initialValue: existingRule != nil)
        _recurrenceFrequency = State(initialValue: existingRule?.frequency ?? .monthly)
        _recurrenceWeekday = State(initialValue: existingRule?.weekday ?? Calendar.current.component(.weekday, from: transaction?.date ?? .now))
    }

    private var categories: [FinanceCategory] {
        store.categories(for: type)
    }

    private var favouriteCategories: [FinanceCategory] {
        Array(categories.filter { $0.parentID == nil }.prefix(8))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loại giao dịch") {
                    Picker("Loại", selection: $mode) {
                        ForEach(TransactionEntryMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Số tiền") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AmountTextField(text: $amountText, placeholder: "0", fontSize: 26).frame(height: 38)
                            .accessibilityLabel("Số tiền")
                        Text(store.preferences.currencyCode)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FinanceStyle.muted)
                    }
                }

                Section(mode == .transfer ? "Chuyển giữa các ví" : "Thông tin") {
                    if mode == .transfer {
                        Picker("Ví nguồn", selection: $walletID) {
                            ForEach(store.wallets) { wallet in Text(wallet.name).tag(wallet.id) }
                        }
                        Picker("Ví đích", selection: $destinationWalletID) {
                            ForEach(store.wallets.filter { $0.id != walletID }) { wallet in Text(wallet.name).tag(wallet.id) }
                        }
                    } else {
                        TextField(type == .expense ? "Ví dụ: Cà phê sáng" : "Ví dụ: Lương tháng này", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel("Tên giao dịch")
                    }
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    DatePicker("Thời gian", selection: $date, displayedComponents: .hourAndMinute)
                    if mode != .transfer {
                        Picker("Ví", selection: $walletID) {
                            ForEach(store.wallets) { wallet in Text(wallet.name).tag(wallet.id) }
                        }
                    }
                }

                if mode == .transfer {
                    Section("Phí giao dịch (không bắt buộc)") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            AmountTextField(text: $transferFeeText, placeholder: "0", fontSize: 20).frame(height: 34)
                            Text(store.preferences.currencyCode).foregroundStyle(FinanceStyle.muted)
                        }
                        Text("Phí được ghi là khoản chi riêng và được tính vào báo cáo, còn số tiền chuyển chỉ luân chuyển giữa hai ví.")
                            .font(.footnote).foregroundStyle(FinanceStyle.muted)
                    }
                } else {
                Section("Danh mục") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                        ForEach(favouriteCategories) { item in
                            Button { selectCategory(item) } label: {
                                VStack(spacing: 7) {
                                    CategoryIcon(category: item, size: 42)
                                    Text(categoryTitle(item))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(FinanceStyle.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(category == item ? item.tint.opacity(0.18) : FinanceStyle.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(category == item ? item.tint : .clear, lineWidth: 2))
                                .foregroundStyle(FinanceStyle.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                    if categories.count > favouriteCategories.count {
                        Button {
                            showingCategoryPicker = true
                        } label: {
                            HStack {
                                Label("Chọn danh mục khác", systemImage: "list.bullet.rectangle.portrait")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FinanceStyle.purple)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }

                Section("Ghi chú") {
                    TextField("Thêm thông tin (không bắt buộc)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if mode != .transfer {
                Section("Báo cáo") {
                    Toggle("Tính giao dịch này vào báo cáo", isOn: $includeInReports)
                    Text("Tắt để loại khoản này khỏi tổng thu chi và biểu đồ. Số dư ví vẫn được cập nhật.")
                        .font(.footnote).foregroundStyle(FinanceStyle.muted)
                }

                Section("Giao dịch định kỳ") {
                    Toggle("Lặp lại giao dịch này", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Chu kỳ", selection: $recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
                        }
                        if recurrenceFrequency == .weekly || recurrenceFrequency == .biweekly {
                            Picker("Ngày lặp", selection: $recurrenceWeekday) {
                                ForEach(1...7, id: \.self) { value in
                                    Text(FinanceDate.weekdayTitle(value)).tag(value)
                                }
                            }
                        }
                    }
                }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(FinanceStyle.background)
            .navigationTitle(transaction == nil ? "Thêm giao dịch" : "Sửa giao dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .fontWeight(.bold)
                }
                if let transaction {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            store.deleteTransaction(id: transaction.id)
                            dismiss()
                        } label: {
                            Label("Xóa giao dịch", systemImage: "trash")
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Xong") { Keyboard.dismiss() }
                }
            }
            .onChange(of: mode) { newMode in
                type = newMode.transactionType
                if newMode == .transfer { isRecurring = false }
                if newMode != .transfer, !categoriesFor(newMode.transactionType).contains(category) {
                    selectCategory(categoriesFor(newMode.transactionType).first ?? .other)
                }
            }
            .onChange(of: walletID) { source in
                if destinationWalletID == source {
                    destinationWalletID = store.wallets.first(where: { $0.id != source })?.id ?? source
                }
            }
            .onChange(of: type) { newType in
                if !categoriesFor(newType).contains(category) {
                    selectCategory(categoriesFor(newType).first ?? .other)
                }
            }
            .onChange(of: category) { updateAutomaticTitle(for: $0) }
            .onChange(of: title) { value in
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                usesCategoryAsTitle = clean.isEmpty || clean == category.name
            }
            .alert("Chưa thể lưu giao dịch", isPresented: $showingValidationError) {
                Button("Đã hiểu", role: .cancel) { }
            } message: {
                Text("Vui lòng nhập số tiền lớn hơn 0.")
            }
        }
        .background(KeyboardDismissOnTap())
        .sheet(isPresented: $showingCategoryPicker) {
            CategorySelectionView(categories: categories, selected: $category)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func categoriesFor(_ value: TransactionType) -> [FinanceCategory] {
        store.categories(for: value)
    }

    private func categoryTitle(_ item: FinanceCategory) -> String {
        guard let parentID = item.parentID, let parent = store.categories.first(where: { $0.id == parentID }) else { return item.name }
        return "\(parent.name) › \(item.name)"
    }

    private func selectCategory(_ item: FinanceCategory) {
        category = item
        updateAutomaticTitle(for: item)
    }

    private func updateAutomaticTitle(for item: FinanceCategory) {
        if usesCategoryAsTitle { title = item.name }
    }

    private func save() {
        guard let amount = AmountInput.parse(amountText), amount > 0 else {
            showingValidationError = true
            return
        }
        if mode == .transfer {
            guard let source = store.wallets.first(where: { $0.id == walletID }),
                  let destination = store.wallets.first(where: { $0.id == destinationWalletID }),
                  source.id != destination.id else {
                showingValidationError = true
                return
            }
            let fee = AmountInput.parse(transferFeeText) ?? 0
            guard fee >= 0 else { showingValidationError = true; return }
            if let transaction { store.deleteTransaction(id: transaction.id) }
            store.transfer(amount: amount, from: source, to: destination, fee: fee, date: date, note: note)
            dismiss()
            return
        }
        if let transaction, transaction.isInternalTransfer {
            store.deleteTransaction(id: transaction.id)
        }
        var saved = transaction?.isInternalTransfer == true ? FinanceTransaction(title: title, amount: amount, type: type, category: category) : (transaction ?? FinanceTransaction(title: title, amount: amount, type: type, category: category))
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.title = cleanTitle.isEmpty ? category.name : cleanTitle
        saved.amount = amount
        saved.date = date
        saved.type = type
        saved.category = category
        if let wallet = store.wallets.first(where: { $0.id == walletID }) {
            saved.account = wallet.name
            saved.walletID = wallet.id
        }
        saved.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.includeInReports = includeInReports
        if isRecurring {
            let ruleID = transaction?.recurrenceID ?? UUID()
            saved.recurrenceID = ruleID
            let priorRule = store.recurringRules.first(where: { $0.id == ruleID })
            let weekday = (recurrenceFrequency == .weekly || recurrenceFrequency == .biweekly) ? recurrenceWeekday : nil
            let nextDate = priorRule?.nextDate ?? recurrenceFrequency.next(after: date, weekday: weekday)
            store.setRecurringRule(RecurringRule(id: ruleID, title: saved.title, amount: amount, type: type, category: category, walletID: saved.walletID, account: saved.account, note: saved.note, frequency: recurrenceFrequency, weekday: weekday, nextDate: nextDate))
        } else if let ruleID = transaction?.recurrenceID {
            store.deleteRecurringRule(id: ruleID)
            saved.recurrenceID = nil
        }
        store.addOrUpdate(saved)
        dismiss()
    }
}

private struct CategorySelectionView: View {
    let categories: [FinanceCategory]
    @Binding var selected: FinanceCategory
    @Environment(\.dismiss) private var dismiss

    private var parents: [FinanceCategory] { categories.filter { $0.parentID == nil } }
    private func children(of parent: FinanceCategory) -> [FinanceCategory] { categories.filter { $0.parentID == parent.id } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(parents) { parent in
                    Section {
                        categoryRow(parent, isChild: false)
                        ForEach(children(of: parent)) { child in
                            categoryRow(child, isChild: true)
                        }
                    } header: {
                        Label(parent.name, systemImage: parent.symbol)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(FinanceStyle.background)
            .navigationTitle("Chọn danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
    }

    private func categoryRow(_ item: FinanceCategory, isChild: Bool) -> some View {
        Button {
            selected = item
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: item, size: 36)
                Text(isChild ? "↳  \(item.name)" : item.name)
                    .foregroundStyle(FinanceStyle.ink)
                Spacer()
                if selected.id == item.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FinanceStyle.purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: isChild ? 30 : 16, bottom: 5, trailing: 16))
    }
}


import SwiftUI

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case expense = "Chi tiêu"
    case income = "Thu nhập"
    var id: String { rawValue }
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
            .padding(.horizontal, 20)
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
            timeFilterEnabled = true
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

    @State private var type: TransactionType
    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var category: FinanceCategory
    @State private var walletID: UUID
    @State private var note: String
    @State private var usesCategoryAsTitle: Bool
    @State private var isRecurring: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var showingValidationError = false

    init(store: FinanceStore, transaction: FinanceTransaction? = nil) {
        self.store = store
        self.transaction = transaction
        _type = State(initialValue: transaction?.type ?? .expense)
        _title = State(initialValue: transaction?.title ?? "")
        _amountText = State(initialValue: transaction.map { $0.amount == 0 ? "" : AmountInput.format($0.amount) } ?? "")
        _date = State(initialValue: transaction?.date ?? .now)
        _category = State(initialValue: transaction?.category ?? .food)
        let existingWallet = store.wallets.first(where: { $0.id == transaction?.walletID }) ?? store.wallets.first(where: { $0.name == transaction?.account })
        _walletID = State(initialValue: existingWallet?.id ?? store.wallets.first?.id ?? UUID())
        _note = State(initialValue: transaction?.note ?? "")
        _usesCategoryAsTitle = State(initialValue: transaction.map { $0.title == $0.category.name } ?? true)
        let existingRule = store.recurringRules.first(where: { $0.id == transaction?.recurrenceID })
        _isRecurring = State(initialValue: existingRule != nil)
        _recurrenceFrequency = State(initialValue: existingRule?.frequency ?? .monthly)
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
                    Picker("Loại", selection: $type) {
                        ForEach(TransactionType.allCases) { option in
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

                Section("Thông tin") {
                    TextField(type == .expense ? "Ví dụ: Cà phê sáng" : "Ví dụ: Lương tháng này", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Tên giao dịch")
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    DatePicker("Thời gian", selection: $date, displayedComponents: .hourAndMinute)
                    Picker("Ví", selection: $walletID) {
                        ForEach(store.wallets) { wallet in Text(wallet.name).tag(wallet.id) }
                    }
                }

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
                                .background(category == item ? FinanceStyle.purpleLight : FinanceStyle.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(category == item ? FinanceStyle.purple : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                    if categories.count > favouriteCategories.count {
                        DisclosureGroup("Chọn danh mục khác") {
                            Picker("Danh mục", selection: $category) {
                                ForEach(categories) { item in
                                    Text(categoryTitle(item)).tag(item)
                                }
                            }
                            .onChange(of: category) { item in
                                updateAutomaticTitle(for: item)
                            }
                        }
                    }
                }

                Section("Ghi chú") {
                    TextField("Thêm thông tin (không bắt buộc)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Giao dịch định kỳ") {
                    Toggle("Lặp lại giao dịch này", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Chu kỳ", selection: $recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Xong") { Keyboard.dismiss() }
                }
            }
            .onChange(of: type) { newType in
                if !categoriesFor(newType).contains(category) {
                    selectCategory(categoriesFor(newType).first ?? .other)
                }
            }
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
        var saved = transaction ?? FinanceTransaction(title: title, amount: amount, type: type, category: category)
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
        if isRecurring {
            let ruleID = transaction?.recurrenceID ?? UUID()
            saved.recurrenceID = ruleID
            let priorRule = store.recurringRules.first(where: { $0.id == ruleID })
            let nextDate = priorRule?.nextDate ?? recurrenceFrequency.next(after: date)
            store.setRecurringRule(RecurringRule(id: ruleID, title: saved.title, amount: amount, type: type, category: category, walletID: saved.walletID, account: saved.account, note: saved.note, frequency: recurrenceFrequency, nextDate: nextDate))
        } else if let ruleID = transaction?.recurrenceID {
            store.deleteRecurringRule(id: ruleID)
            saved.recurrenceID = nil
        }
        store.addOrUpdate(saved)
        dismiss()
    }
}


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
    @State private var editingTransaction: FinanceTransaction?

    private var filteredTransactions: [FinanceTransaction] {
        store.transactions
            .filter { transaction in
                (filter == .all || (filter == .expense && transaction.type == .expense) || (filter == .income && transaction.type == .income))
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

                if filteredTransactions.isEmpty {
                    EmptyState(
                        symbol: searchText.isEmpty ? "arrow.left.arrow.right" : "magnifyingglass",
                        title: searchText.isEmpty ? "Chưa có giao dịch" : "Không tìm thấy kết quả",
                        message: searchText.isEmpty ? "Nhấn nút + để thêm thu nhập hoặc chi tiêu." : "Thử từ khóa khác hoặc bỏ bộ lọc hiện tại."
                    )
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
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
                        .background(filter == option ? FinanceStyle.purple : .white, in: Capsule())
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
    @State private var account: String
    @State private var note: String
    @State private var showingValidationError = false

    private let accounts = ["Tiền mặt", "Tài khoản ngân hàng", "Thẻ tín dụng"]

    init(store: FinanceStore, transaction: FinanceTransaction? = nil) {
        self.store = store
        self.transaction = transaction
        _type = State(initialValue: transaction?.type ?? .expense)
        _title = State(initialValue: transaction?.title ?? "")
        _amountText = State(initialValue: transaction.map { String($0.amount) } ?? "")
        _date = State(initialValue: transaction?.date ?? .now)
        _category = State(initialValue: transaction?.category ?? .food)
        _account = State(initialValue: transaction?.account ?? "Tiền mặt")
        _note = State(initialValue: transaction?.note ?? "")
    }

    private var categories: [FinanceCategory] {
        type == .expense ? FinanceCategory.expenseCategories : FinanceCategory.incomeCategories
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
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
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
                    Picker("Tài khoản", selection: $account) {
                        ForEach(accounts, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Danh mục") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                        ForEach(categories) { item in
                            Button { category = item } label: {
                                VStack(spacing: 7) {
                                    CategoryIcon(category: item, size: 42)
                                    Text(item.rawValue)
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
                }

                Section("Ghi chú") {
                    TextField("Thêm thông tin (không bắt buộc)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .scrollContentBackground(.hidden)
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
            }
            .onChange(of: type) { newType in
                if !categoriesFor(newType).contains(category) {
                    category = categoriesFor(newType).first ?? .other
                }
            }
            .alert("Chưa thể lưu giao dịch", isPresented: $showingValidationError) {
                Button("Đã hiểu", role: .cancel) { }
            } message: {
                Text("Vui lòng nhập nội dung và số tiền lớn hơn 0.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func categoriesFor(_ value: TransactionType) -> [FinanceCategory] {
        value == .expense ? FinanceCategory.expenseCategories : FinanceCategory.incomeCategories
    }

    private func save() {
        let normalizedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalizedAmount), amount > 0, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingValidationError = true
            return
        }
        var saved = transaction ?? FinanceTransaction(title: title, amount: amount, type: type, category: category)
        saved.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.amount = amount
        saved.date = date
        saved.type = type
        saved.category = category
        saved.account = account
        saved.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addOrUpdate(saved)
        dismiss()
    }
}

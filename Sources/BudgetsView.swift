import SwiftUI

struct BudgetsView: View {
    @ObservedObject var store: FinanceStore
    @State private var activeSheet: BudgetSheet?
    @State private var month = Date()

    private enum BudgetSheet: Identifiable {
        case add
        case edit(SpendingBudget)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let budget): return budget.id.uuidString
            }
        }
    }

    private var totalLimit: Double { store.budgets.reduce(0) { $0 + $1.monthlyLimit } }
    private var totalSpent: Double { store.budgets.reduce(0) { $0 + store.spent(for: $1.category, in: month) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                monthPicker
                overviewCard
                SectionHeading(title: "Theo danh mục", actionTitle: "＋ Thêm") { activeSheet = .add }
                if store.budgets.isEmpty {
                    EmptyState(symbol: "target", title: "Chi tiêu có kế hoạch", message: "Tạo ngân sách theo danh mục để biết mình đang đi đúng hướng.")
                        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.budgets.sorted { $0.category.rawValue < $1.category.rawValue }) { budget in
                            budgetCard(budget)
                                .onTapGesture { activeSheet = .edit(budget) }
                                .contextMenu {
                                    Button(role: .destructive) { store.deleteBudget(id: budget.id) } label: {
                                        Label("Xóa ngân sách", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                Text("Mẹo: nhấn giữ một ngân sách để xóa, hoặc chạm để điều chỉnh giới hạn.")
                    .font(.system(size: 12))
                    .foregroundStyle(FinanceStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 110)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                BudgetEditorView(store: store)
            case .edit(let budget):
                BudgetEditorView(store: store, budget: budget)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHI TIÊU CÓ KẾ HOẠCH")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FinanceStyle.purple)
            Text("Ngân sách")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Theo dõi giới hạn chi tiêu của bạn")
                .font(.system(size: 14))
                .foregroundStyle(FinanceStyle.muted)
        }
    }

    private var monthPicker: some View {
        HStack {
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38) }
                .accessibilityLabel("Tháng trước")
            Spacer()
            Text(DateText.monthYear(month)).font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 38) }
                .accessibilityLabel("Tháng sau")
        }
        .foregroundStyle(FinanceStyle.ink)
        .background(FinanceStyle.card, in: Capsule())
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ĐÃ SỬ DỤNG")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(MoneyText.string(totalSpent, currencyCode: store.preferences.currencyCode))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            HStack {
                Label("Ngân sách", systemImage: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(MoneyText.string(totalLimit, currencyCode: store.preferences.currencyCode))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(hex: 0x35BA91), Color(hex: 0x168E78)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func budgetCard(_ budget: SpendingBudget) -> some View {
        let spent = store.spent(for: budget.category, in: month)
        let ratio = budget.monthlyLimit > 0 ? spent / budget.monthlyLimit : 0
        let over = ratio >= 1
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CategoryIcon(category: budget.category, size: 45)
                VStack(alignment: .leading, spacing: 4) {
                    Text(budget.category.rawValue).font(.system(size: 15, weight: .bold)).foregroundStyle(FinanceStyle.ink)
                    Text(over ? "Đã vượt giới hạn" : "Còn \(MoneyText.string(max(0, budget.monthlyLimit - spent), currencyCode: store.preferences.currencyCode))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(over ? FinanceStyle.red : FinanceStyle.muted)
                }
                Spacer()
                Text("\(Int(ratio * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(over ? FinanceStyle.red : budget.category.tint)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FinanceStyle.background)
                    Capsule().fill(over ? FinanceStyle.red : budget.category.tint).frame(width: max(8, proxy.size.width * min(ratio, 1)))
                }
            }
            .frame(height: 8)
            HStack {
                Text(MoneyText.string(spent, currencyCode: store.preferences.currencyCode)).fontWeight(.semibold).foregroundStyle(FinanceStyle.ink)
                Spacer()
                Text("Giới hạn \(MoneyText.string(budget.monthlyLimit, currencyCode: store.preferences.currencyCode))").foregroundStyle(FinanceStyle.muted)
            }
            .font(.system(size: 12))
        }
        .padding(17)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func changeMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: month) { month = next }
    }
}

struct BudgetEditorView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let budget: SpendingBudget?
    @State private var category: FinanceCategory
    @State private var limitText: String
    @State private var showingValidationError = false

    init(store: FinanceStore, budget: SpendingBudget? = nil) {
        self.store = store
        self.budget = budget
        _category = State(initialValue: budget?.category ?? .food)
        _limitText = State(initialValue: budget.map { String($0.monthlyLimit) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Danh mục") {
                    Picker("Danh mục", selection: $category) {
                        ForEach(store.categories(for: .expense).filter { $0.parentID == nil }) { item in
                            Label(item.name, systemImage: item.symbol).tag(item)
                        }
                    }
                }
                Section("Giới hạn mỗi tháng") {
                    HStack {
                        TextField("0", text: $limitText).keyboardType(.decimalPad).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(store.preferences.currencyCode).foregroundStyle(FinanceStyle.muted)
                    }
                }
                Section {
                    Text("Bạn sẽ thấy thanh tiến độ cập nhật theo các giao dịch thuộc danh mục này.")
                        .font(.system(size: 13)).foregroundStyle(FinanceStyle.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinanceStyle.background)
            .navigationTitle(budget == nil ? "Ngân sách mới" : "Sửa ngân sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { save() }.fontWeight(.bold) }
            }
            .alert("Số tiền chưa hợp lệ", isPresented: $showingValidationError) {
                Button("Đã hiểu", role: .cancel) { }
            } message: {
                Text("Nhập giới hạn lớn hơn 0.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let normalized = limitText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let limit = Double(normalized), limit > 0 else {
            showingValidationError = true
            return
        }
        store.setBudget(SpendingBudget(id: budget?.id ?? UUID(), category: category, monthlyLimit: limit))
        dismiss()
    }
}


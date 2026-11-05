import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: FinanceStore
    let openBudgets: () -> Void
    let openTransactions: () -> Void
    @State private var month = Date()
    @State private var editingTransaction: FinanceTransaction?
    @AppStorage("isBalanceHidden") private var isBalanceHidden = false

    private var monthTransactions: [FinanceTransaction] { store.transactions(in: month).sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 23) {
                header
                monthPicker
                balanceCard
                recentSection
                budgetPreview
                privacyNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 112)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditorView(store: store, transaction: transaction)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("QUẢN LÝ TÀI CHÍNH")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(FinanceStyle.purple)
                Text("Xin chào 👋")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(FinanceStyle.ink)
            }
            Spacer()
            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FinanceStyle.green)
                .frame(width: 50, height: 50)
                .background(FinanceStyle.card, in: Circle())
                .overlay(Circle().stroke(FinanceStyle.line, lineWidth: 1))
                .accessibilityLabel("Liquid Finance")
        }
    }

    private var monthPicker: some View {
        MonthNavigator(month: $month)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Tổng số dư", systemImage: "creditcard.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBalanceHidden.toggle()
                    }
                } label: {
                    Image(systemName: isBalanceHidden ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isBalanceHidden ? "Hiện số dư" : "Ẩn số dư")
                .accessibilityHint(isBalanceHidden ? "Chạm để hiện tổng số dư" : "Chạm để ẩn tổng số dư")
            }
            Text(isBalanceHidden ? "•••••••• đ" : MoneyText.string(store.balance, currencyCode: store.preferences.currencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.68)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityLabel(isBalanceHidden ? "Số dư đã ẩn" : "Số dư \(MoneyText.string(store.balance, currencyCode: store.preferences.currencyCode))")
            HStack(spacing: 0) {
                balanceSummary(title: "Thu nhập", amount: store.total(for: .income, in: month), symbol: "arrow.down.left", tint: Color(hex: 0x8FE4BD))
                Spacer(minLength: 12)
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 38)
                Spacer(minLength: 12)
                balanceSummary(title: "Chi tiêu", amount: store.total(for: .expense, in: month), symbol: "arrow.up.right", tint: Color(hex: 0xFFC1C4))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            LinearGradient(colors: [Color(hex: 0x5545B8), Color(hex: 0x342774)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: FinanceStyle.purple.opacity(0.22), radius: 18, x: 0, y: 10)
        .onAppear { store.syncBalanceVisibility(isBalanceHidden) }
        .onChange(of: isBalanceHidden) { store.syncBalanceVisibility($0) }
    }

    private func balanceSummary(title: String, amount: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text(isBalanceHidden ? "•••••••• đ" : MoneyText.string(amount, currencyCode: store.preferences.currencyCode))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Giao dịch gần đây", actionTitle: "Tất cả", action: openTransactions)
            if monthTransactions.isEmpty {
                EmptyState(symbol: "tray", title: "Chưa có giao dịch", message: "Thêm khoản thu hoặc chi đầu tiên để theo dõi dòng tiền của bạn.")
                    .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(monthTransactions.prefix(4).enumerated()), id: \.element.id) { index, transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRow(transaction: transaction, currencyCode: store.preferences.currencyCode)
                        }
                        .buttonStyle(.plain)
                        if index < min(monthTransactions.count, 4) - 1 {
                            Divider().overlay(FinanceStyle.line).padding(.leading, 64)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var budgetPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Ngân sách tháng", actionTitle: "Quản lý") { openBudgets() }
            if store.budgets.isEmpty {
                Button(action: openBudgets) {
                    HStack(spacing: 14) {
                        Image(systemName: "target")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(FinanceStyle.purple)
                            .frame(width: 48, height: 48)
                            .background(FinanceStyle.purpleLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lập ngân sách đầu tiên")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(FinanceStyle.ink)
                            Text("Đặt giới hạn chi tiêu theo danh mục")
                                .font(.system(size: 13))
                                .foregroundStyle(FinanceStyle.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(FinanceStyle.muted)
                    }
                    .padding(16)
                    .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    ForEach(store.budgets.prefix(3)) { budget in
                        let periodRange = budget.period.range(containing: month)
                        let spent = store.spent(for: budget, from: periodRange.0, through: periodRange.1)
                        let warning = spent >= budget.monthlyLimit * 0.8 && spent < budget.monthlyLimit
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(budget.categoryIDs.compactMap { id in store.categories.first(where: { $0.id == id })?.name }.joined(separator: ", "), systemImage: budget.category.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(FinanceStyle.ink)
                                Spacer()
                                Text("\(MoneyText.string(spent, currencyCode: store.preferences.currencyCode)) / \(MoneyText.string(budget.monthlyLimit, currencyCode: store.preferences.currencyCode))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FinanceStyle.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            if warning {
                                Label("Đã dùng từ 80% ngân sách \(budget.period.title.lowercased())", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0xE7A940))
                            }
                            ProgressView(value: budget.monthlyLimit > 0 ? min(spent / budget.monthlyLimit, 1) : 0)
                                .tint(spent >= budget.monthlyLimit ? FinanceStyle.red : budget.category.tint)
                        }
                        .padding(16)
                        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill").foregroundStyle(FinanceStyle.green)
            Text("Dữ liệu được lưu riêng tư trên iPhone của bạn.")
                .foregroundStyle(FinanceStyle.muted)
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    let currencyCode: String
    private var subtitle: String {
        let categoryName = transaction.isInternalTransfer ? "Chuyển khoản nội bộ" : transaction.category.rawValue
        return "\(categoryName) · \(DateText.dateTime(transaction.date))"
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FinanceStyle.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(FinanceStyle.muted)
                    .lineLimit(1)
                Text(transaction.account)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FinanceStyle.purple)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(transaction.type == .income ? "+" : "−")\(MoneyText.string(transaction.amount, currencyCode: currencyCode))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(transaction.type == .income ? FinanceStyle.green : FinanceStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}


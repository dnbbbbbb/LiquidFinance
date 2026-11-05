import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: FinanceStore
    let openBudgets: () -> Void
    let openTransactions: () -> Void
    @State private var month = Date()
    @State private var editingTransaction: FinanceTransaction?

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
            .padding(.horizontal, 20)
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
        HStack(spacing: 14) {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FinanceStyle.muted)
                    .frame(width: 34, height: 34)
                    .background(FinanceStyle.card, in: Circle())
            }
            .accessibilityLabel("Tháng trước")
            Text(DateText.monthYear(month))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FinanceStyle.ink)
                .frame(minWidth: 130)
            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FinanceStyle.muted)
                    .frame(width: 34, height: 34)
                    .background(FinanceStyle.card, in: Circle())
            }
            .accessibilityLabel("Tháng sau")
            Spacer()
            Text("THÁNG")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(FinanceStyle.muted)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Tổng số dư", systemImage: "creditcard.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Button {
                    store.updatePreferences { $0.hidesBalance.toggle() }
                } label: {
                    Image(systemName: store.preferences.hidesBalance ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityLabel(store.preferences.hidesBalance ? "Hiện số dư" : "Ẩn số dư")
            }
            Text(store.preferences.hidesBalance ? "••••••••" : MoneyText.string(store.balance, currencyCode: store.preferences.currencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.68)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityLabel(store.preferences.hidesBalance ? "Số dư đã ẩn" : "Số dư \(MoneyText.string(store.balance, currencyCode: store.preferences.currencyCode))")
            HStack(spacing: 0) {
                balanceSummary(title: "Thu nhập", amount: store.total(for: .income, in: month), symbol: "arrow.down.left", tint: Color(hex: 0x8FE4BD))
                Spacer(minLength: 12)
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 38)
                Spacer(minLength: 12)
                balanceSummary(title: "Chi tiêu", amount: store.total(for: .expense, in: month), symbol: "arrow.up.right", tint: Color(hex: 0xFFC1C4))
            }
        }
        .padding(22)
        .background(
            LinearGradient(colors: [Color(hex: 0x7970FF), Color(hex: 0x5147D5)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle().fill(.white.opacity(0.05)).frame(width: 160).offset(x: 40, y: -65).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: FinanceStyle.purple.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private func balanceSummary(title: String, amount: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Text(store.preferences.hidesBalance ? "••••" : MoneyText.string(amount, currencyCode: store.preferences.currencyCode))
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
                        let spent = store.spent(for: budget.category, in: month)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(budget.category.rawValue, systemImage: budget.category.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(FinanceStyle.ink)
                                Spacer()
                                Text("\(MoneyText.string(spent, currencyCode: store.preferences.currencyCode)) / \(MoneyText.string(budget.monthlyLimit, currencyCode: store.preferences.currencyCode))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FinanceStyle.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
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

    private func moveMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: month) { month = next }
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FinanceStyle.ink)
                    .lineLimit(1)
                Text("\(transaction.category.rawValue) · \(DateText.dayMonth(transaction.date))")
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


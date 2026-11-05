import SwiftUI
import Charts

private struct MonthlySpend: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let amount: Double
}

private struct CategorySpend: Identifiable {
    let category: FinanceCategory
    let amount: Double
    var id: String { category.rawValue }
}

struct ReportsView: View {
    @ObservedObject var store: FinanceStore
    @State private var month = Date()

    private var monthExpense: Double { store.total(for: .expense, in: month) }
    private var monthIncome: Double { store.total(for: .income, in: month) }
    private var categoryTotals: [CategorySpend] {
        FinanceCategory.expenseCategories
            .map { CategorySpend(category: $0, amount: store.spent(for: $0, in: month)) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }
    private var monthlySeries: [MonthlySpend] {
        let calendar = Calendar.current
        return (0..<6).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: FinanceDate.startOfMonth(containing: month)) else { return nil }
            return MonthlySpend(date: date, label: DateText.compactMonth(date), amount: store.total(for: .expense, in: date))
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                monthPicker
                summaryCards
                trendCard
                categoriesCard
                insightCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 110)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NHÌN LẠI DÒNG TIỀN")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FinanceStyle.purple)
            Text("Báo cáo")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Mỗi ngày một chút, tài chính thêm rõ ràng.")
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
        .background(.white, in: Capsule())
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Thu nhập", amount: monthIncome, icon: "arrow.down.left", color: FinanceStyle.green, background: FinanceStyle.greenLight)
            summaryCard(title: "Chi tiêu", amount: monthExpense, icon: "arrow.up.right", color: FinanceStyle.red, background: FinanceStyle.redLight)
        }
    }

    private func summaryCard(title: String, amount: Double, icon: String, color: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(FinanceStyle.muted)
            Text(MoneyText.string(amount, currencyCode: store.preferences.currencyCode))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Chi tiêu 6 tháng")
            if monthlySeries.allSatisfy({ $0.amount == 0 }) {
                EmptyState(symbol: "chart.bar", title: "Biểu đồ đang chờ dữ liệu", message: "Các khoản chi sẽ xuất hiện tại đây.")
            } else {
                Chart(monthlySeries) { item in
                    BarMark(
                        x: .value("Tháng", item.label),
                        y: .value("Chi tiêu", item.amount)
                    )
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x958EFF), FinanceStyle.purple], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(6)
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
                .accessibilityLabel("Biểu đồ chi tiêu trong 6 tháng gần đây")
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Chi tiêu theo danh mục")
            if categoryTotals.isEmpty {
                Text("Chưa có khoản chi trong tháng này.")
                    .font(.system(size: 14))
                    .foregroundStyle(FinanceStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(categoryTotals) { item in
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            CategoryIcon(category: item.category, size: 36)
                            Text(item.category.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(FinanceStyle.ink)
                            Spacer()
                            Text(MoneyText.string(item.amount, currencyCode: store.preferences.currencyCode))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(FinanceStyle.ink)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(FinanceStyle.background)
                                Capsule().fill(item.category.tint).frame(width: max(5, proxy.size.width * item.amount / monthExpense))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color(hex: 0xE7A940))
                .frame(width: 42, height: 42)
                .background(Color(hex: 0xFFF6E3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("Gợi ý của bạn").font(.system(size: 14, weight: .bold)).foregroundStyle(FinanceStyle.ink)
                Text(categoryTotals.first.map { "\($0.category.rawValue) đang là danh mục chi tiêu lớn nhất tháng này." } ?? "Ghi lại các khoản chi để khám phá thói quen tài chính của bạn.")
                    .font(.system(size: 13))
                    .foregroundStyle(FinanceStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func changeMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: month) { month = next }
    }
}

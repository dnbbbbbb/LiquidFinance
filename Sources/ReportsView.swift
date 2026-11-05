import SwiftUI
import Charts

private struct MonthlySpend: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let amount: Double
}

private enum ReportChartMode: String, CaseIterable, Identifiable {
    case days = "Theo ngày"
    case months = "Theo tháng"
    var id: String { rawValue }
}

private struct CategorySpend: Identifiable {
    let category: FinanceCategory
    let amount: Double
    var id: String { category.rawValue }
}

struct ReportsView: View {
    @ObservedObject var store: FinanceStore
    @State private var month = Date()
    @State private var timeFilterEnabled = false
    @State private var rangeStart = FinanceDate.startOfMonth(containing: .now)
    @State private var rangeEnd = Date.now
    @State private var chartMode: ReportChartMode = .months

    private var effectiveStart: Date { timeFilterEnabled ? min(rangeStart, rangeEnd) : .distantPast }
    private var effectiveEnd: Date { timeFilterEnabled ? max(rangeStart, rangeEnd) : .distantFuture }
    private var monthExpense: Double { store.total(for: .expense, from: effectiveStart, through: effectiveEnd) }
    private var monthIncome: Double { store.total(for: .income, from: effectiveStart, through: effectiveEnd) }
    private var categoryTotals: [CategorySpend] {
        store.categories(for: .expense).filter { $0.parentID == nil }
            .map { CategorySpend(category: $0, amount: store.spent(for: $0, from: effectiveStart, through: effectiveEnd)) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }
    private var monthlySeries: [MonthlySpend] {
        let calendar = Calendar.current
        let currentMonth = FinanceDate.startOfMonth(containing: month)
        let firstMonth = timeFilterEnabled
            ? FinanceDate.startOfMonth(containing: min(rangeStart, rangeEnd))
            : (calendar.date(byAdding: .month, value: -5, to: currentMonth) ?? currentMonth)
        let lastMonth = timeFilterEnabled
            ? FinanceDate.startOfMonth(containing: max(rangeStart, rangeEnd))
            : currentMonth
        let monthCount = max(1, (calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0) + 1)
        return (0..<monthCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: firstMonth),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
            let start = timeFilterEnabled ? max(date, min(rangeStart, rangeEnd)) : date
            let end = timeFilterEnabled ? min(nextMonth.addingTimeInterval(-1), max(rangeStart, rangeEnd)) : nextMonth.addingTimeInterval(-1)
            return MonthlySpend(date: date, label: DateText.compactMonth(date), amount: store.total(for: .expense, from: start, through: end))
        }
    }

    private var dailySeries: [MonthlySpend] {
        let calendar = Calendar.current
        let startOfMonth = FinanceDate.startOfMonth(containing: month)
        guard let days = calendar.range(of: .day, in: .month, for: startOfMonth) else { return [] }
        return days.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth),
                  let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            let start = max(date, effectiveStart)
            let end = min(next.addingTimeInterval(-1), effectiveEnd)
            let amount = start <= end ? store.total(for: .expense, from: start, through: end) : 0
            return MonthlySpend(date: date, label: String(day), amount: amount)
        }
    }

    private var chartSeries: [MonthlySpend] { chartMode == .days ? dailySeries : monthlySeries }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                MonthNavigator(month: $month)
                DateRangeFilterView(isEnabled: $timeFilterEnabled, start: $rangeStart, end: $rangeEnd)
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
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: chartMode == .days ? "Chi tiêu theo ngày" : (timeFilterEnabled ? "Chi tiêu theo tháng" : "Chi tiêu 6 tháng"))
            Picker("Kiểu biểu đồ", selection: $chartMode) {
                ForEach(ReportChartMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if chartSeries.allSatisfy({ $0.amount == 0 }) {
                EmptyState(symbol: "chart.bar", title: "Biểu đồ đang chờ dữ liệu", message: "Các khoản chi sẽ xuất hiện tại đây.")
            } else {
                Chart(chartSeries) { item in
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
                .accessibilityLabel(chartMode == .days ? "Biểu đồ chi tiêu từng ngày" : "Biểu đồ chi tiêu theo tháng")
            }
        }
        .padding(18)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

}


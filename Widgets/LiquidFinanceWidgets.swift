import WidgetKit
import SwiftUI

private let sharedDefaults = UserDefaults(suiteName: "group.vn.liquidfinance")

struct FinanceWidgetEntry: TimelineEntry {
    let date: Date
    let balance: Double
    let currency: String
    let isHidden: Bool
}

struct FinanceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinanceWidgetEntry { FinanceWidgetEntry(date: .now, balance: 12_500_000, currency: "VND", isHidden: false) }
    func getSnapshot(in context: Context, completion: @escaping (FinanceWidgetEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date.now.addingTimeInterval(15 * 60))))
    }
    private func entry() -> FinanceWidgetEntry {
        FinanceWidgetEntry(
            date: .now,
            balance: sharedDefaults?.double(forKey: "finance.widget.balance") ?? 0,
            currency: sharedDefaults?.string(forKey: "finance.widget.currency") ?? "VND",
            isHidden: sharedDefaults?.bool(forKey: "finance.widget.hidesBalance") ?? false
        )
    }
}

private func money(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "vi_VN")
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = currency == "VND" ? 0 : 2
    return formatter.string(from: NSNumber(value: amount)) ?? "0 \(currency)"
}

struct BalanceWidget: Widget {
    let kind = "LiquidFinanceBalance"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceWidgetProvider()) { entry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.30, green: 0.27, blue: 0.82), Color(red: 0.46, green: 0.22, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Label("Tổng số dư", systemImage: "wallet.pass.fill"); Spacer(); Image(systemName: entry.isHidden ? "eye.slash" : "eye") }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                    Text(entry.isHidden ? "••••••••" : money(entry.balance, currency: entry.currency))
                        .font(.title3.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Text("Liquid Finance").font(.caption2).foregroundStyle(.white.opacity(0.75))
                }
                .padding()
            }
            .widgetURL(URL(string: "liquidfinance://dashboard"))
        }
        .configurationDisplayName("Số dư Liquid Finance")
        .description("Xem nhanh tổng số dư của bạn.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickEntryWidget: Widget {
    let kind = "LiquidFinanceQuickEntry"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceWidgetProvider()) { _ in
            Link(destination: URL(string: "liquidfinance://add-transaction")!) {
                ZStack {
                    Color(red: 0.08, green: 0.62, blue: 0.48)
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 34))
                        Text("Nhập giao dịch nhanh").font(.headline).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white).padding()
                }
            }
        }
        .configurationDisplayName("Nhập nhanh")
        .description("Mở ngay biểu mẫu ghi giao dịch.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct LiquidFinanceWidgets: WidgetBundle {
    var body: some Widget { BalanceWidget(); QuickEntryWidget() }
}

import SwiftUI

enum FinanceTab: Hashable {
    case home
    case transactions
    case budgets
    case reports
    case settings
}

struct ContentView: View {
    @ObservedObject var store: FinanceStore
    @State private var selectedTab: FinanceTab = .home
    @State private var showingNewTransaction = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DashboardView(
                    store: store,
                    openBudgets: { selectedTab = .budgets },
                    openTransactions: { selectedTab = .transactions }
                )
                    .tabItem { Label("Tổng quan", systemImage: "square.grid.2x2.fill") }
                    .tag(FinanceTab.home)

                TransactionsView(store: store)
                    .tabItem { Label("Giao dịch", systemImage: "arrow.left.arrow.right") }
                    .tag(FinanceTab.transactions)

                BudgetsView(store: store)
                    .tabItem { Label("Ngân sách", systemImage: "chart.pie.fill") }
                    .tag(FinanceTab.budgets)

                ReportsView(store: store)
                    .tabItem { Label("Báo cáo", systemImage: "chart.bar.xaxis") }
                    .tag(FinanceTab.reports)

                SettingsView(store: store)
                    .tabItem { Label("Cài đặt", systemImage: "slider.horizontal.3") }
                    .tag(FinanceTab.settings)
            }
            .tint(FinanceStyle.purple)

            Button {
                showingNewTransaction = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x8178FF), FinanceStyle.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: FinanceStyle.purple.opacity(0.35), radius: 12, x: 0, y: 7)
            }
            .accessibilityLabel("Thêm giao dịch")
            .padding(.trailing, 22)
            .padding(.bottom, 76)
        }
        .sheet(isPresented: $showingNewTransaction) {
            TransactionEditorView(store: store)
        }
        .preferredColorScheme(.light)
    }
}

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
    @ObservedObject var cloudSync: ICloudSyncViewModel
    @Environment(\.scenePhase) private var scenePhase
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

                SettingsView(store: store, cloudSync: cloudSync)
                    .tabItem { Label("Cài đặt", systemImage: "slider.horizontal.3") }
                    .tag(FinanceTab.settings)
            }
            .tint(FinanceStyle.purple)
            .toolbarBackground(FinanceStyle.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinanceStyle.background.ignoresSafeArea())
        .sheet(isPresented: $showingNewTransaction) {
            TransactionEditorView(store: store)
        }
        .onAppear { store.processDueRecurringTransactions() }
        .task {
            await cloudSync.refreshConnection()
            guard store.transactions.isEmpty, store.budgets.isEmpty,
                  let snapshot = cloudSync.latestSnapshot() else { return }
            try? store.restoreBackup(snapshot)
        }
        .onReceive(NotificationCenter.default.publisher(for: FinanceStore.didChangeNotification)) { _ in
            DispatchQueue.main.async {
                if let snapshot = try? store.backupData() { cloudSync.scheduleSynchronization(snapshot: snapshot) }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.processDueRecurringTransactions()
                if let snapshot = cloudSync.newerRemoteSnapshot() { try? store.restoreBackup(snapshot) }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "liquidfinance" else { return }
            if url.host == "add-transaction" {
                selectedTab = .transactions
                showingNewTransaction = true
            }
        }
        .preferredColorScheme(store.preferences.appearance == "light" ? .light : (store.preferences.appearance == "dark" ? .dark : nil))
    }
}


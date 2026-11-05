import SwiftUI

@main
struct LiquidFinanceApp: App {
    @StateObject private var store: FinanceStore

    init() {
        let store = FinanceStore()
        _store = StateObject(wrappedValue: store)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isBalanceHidden") == nil {
            defaults.set(store.preferences.hidesBalance, forKey: "isBalanceHidden")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.locale, Locale(identifier: "vi_VN"))
        }
    }
}


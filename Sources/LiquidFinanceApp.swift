import SwiftUI

@main
struct LiquidFinanceApp: App {
    @StateObject private var store: FinanceStore
    @StateObject private var cloudSync = ICloudSyncViewModel()

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
            ContentView(store: store, cloudSync: cloudSync)
                .environment(\.locale, Locale(identifier: "vi_VN"))
        }
    }
}


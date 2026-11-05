import SwiftUI

@main
struct LiquidFinanceApp: App {
    @StateObject private var store = FinanceStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.locale, Locale(identifier: "vi_VN"))
        }
    }
}


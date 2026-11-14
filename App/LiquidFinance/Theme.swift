import SwiftUI
import LiquidFinanceCore

// MARK: Theme Engine
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, pink
    var id: String { rawValue }
    var title: String { ["system": "Theo hệ thống", "light": "Sáng", "dark": "Tối", "pink": "Hồng"][rawValue]! }
}

struct Palette {
    let background: Color, surface: Color, primary: Color, accent: Color, text: Color, secondaryText: Color
    let income: Color, expense: Color
    static let light = Palette(background: Color(hex: "#F5F6F8"), surface: .white, primary: Color(hex: "#0A84FF"), accent: Color(hex: "#5E5CE6"),
                               text: Color(hex: "#111114"), secondaryText: Color(hex: "#6B6B73"), income: Color(hex: "#1E9E5A"), expense: Color(hex: "#E5484D"))
    static let dark = Palette(background: Color(hex: "#0B0B0E"), surface: Color(hex: "#1B1B20"), primary: Color(hex: "#4DA3FF"), accent: Color(hex: "#8E8CFF"),
                              text: Color(hex: "#ECECF1"), secondaryText: Color(hex: "#9A9AA5"), income: Color(hex: "#4CD08A"), expense: Color(hex: "#FF7A7F"))
    static let pink = Palette(background: Color(hex: "#FFF3F7"), surface: Color(hex: "#FFFAFC"), primary: Color(hex: "#F7A8C4"), accent: Color(hex: "#E75C8D"),
                              text: Color(hex: "#4A3340"), secondaryText: Color(hex: "#8C6F7E"), income: Color(hex: "#3AA67A"), expense: Color(hex: "#D9486F"))
}

/// Central theme state. Persisted in the database settings table (so it is part of every backup).
@MainActor final class ThemeEngine: ObservableObject {
    @Published var theme: AppTheme = .system
    @Published var systemIsDark = false
    var palette: Palette {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .pink: return .pink
        case .system: return systemIsDark ? .dark : .light
        }
    }
    var colorScheme: ColorScheme? { theme == .system ? nil : (theme == .dark ? .dark : .light) }
    func load(_ s: SettingsStore) { theme = AppTheme(rawValue: (try? s.get(SettingsStore.Key.theme)) ?? "") ?? .system }
    func set(_ t: AppTheme, store: SettingsStore) {
        withAnimation(.smooth) { theme = t }
        try? store.set(SettingsStore.Key.theme, t.rawValue)
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: Liquid Glass with graceful fallback (only for floating controls, never behind numbers/charts)
extension View {
    @ViewBuilder func floatingGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { self.glassEffect(.regular.interactive(), in: shape) }
        else { self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.5)) }
        #else
        self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.5))
        #endif
    }
}

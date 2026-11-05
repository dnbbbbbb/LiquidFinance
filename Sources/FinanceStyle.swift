import SwiftUI
import UIKit

enum FinanceStyle {
    private static let appearanceKey = "finance.active-appearance"

    static func setAppearance(_ appearance: String) {
        UserDefaults.standard.set(appearance, forKey: appearanceKey)
    }

    private static var usesPinkTheme: Bool {
        UserDefaults.standard.string(forKey: appearanceKey) == "sanrio"
    }

    static var background: Color {
        usesPinkTheme
            ? Color(hex: 0xFFF4FA)
            : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1) : UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1) })
    }
    static var card: Color {
        usesPinkTheme ? Color(hex: 0xFFFDFE) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1) : .white })
    }
    static var ink: Color {
        usesPinkTheme ? Color(hex: 0x4D1937) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(red: 0.12, green: 0.13, blue: 0.21, alpha: 1) })
    }
    static var muted: Color {
        usesPinkTheme ? Color(hex: 0x9A6683) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.68, alpha: 1) : UIColor(red: 0.52, green: 0.54, blue: 0.61, alpha: 1) })
    }
    static var purple: Color { usesPinkTheme ? Color(hex: 0xE85D9A) : Color(hex: 0x665DF2) }
    static var purpleLight: Color { usesPinkTheme ? Color(hex: 0xFFE1F0) : Color(hex: 0xEFEDFF) }
    static var green: Color { usesPinkTheme ? Color(hex: 0x45A983) : Color(hex: 0x22A879) }
    static var greenLight: Color { usesPinkTheme ? Color(hex: 0xE2F7ED) : Color(hex: 0xE6F7F0) }
    static var red: Color { usesPinkTheme ? Color(hex: 0xD85C7E) : Color(hex: 0xE66A74) }
    static var redLight: Color { usesPinkTheme ? Color(hex: 0xFFE9EF) : Color(hex: 0xFFF0F0) }
    static var line: Color {
        usesPinkTheme ? Color(hex: 0xF3CEE0) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1) })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension FinanceCategory {
    var tint: Color {
        if let colorHex { return Color(hex: colorHex) }
        switch id {
        case "food": return Color(hex: 0xF09A56)
        case "transport": return Color(hex: 0x5187E8)
        case "shopping": return Color(hex: 0xBD73D7)
        case "housing": return Color(hex: 0xEA7284)
        case "health": return Color(hex: 0x36AFA1)
        case "entertainment": return Color(hex: 0xE1A53C)
        case "education": return Color(hex: 0x5D9F77)
        case "bills": return Color(hex: 0x7F7BE5)
        case "salary": return FinanceStyle.green
        case "bonus": return Color(hex: 0xE1A53C)
        case "investment": return Color(hex: 0x5187E8)
        case "gift": return Color(hex: 0xE66A94)
        default: return Color(hex: 0x9297A8)
        }
    }
}

enum MoneyText {
    static func string(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = ["VND", "JPY", "KRW"].contains(currencyCode) ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currencyCode)"
    }
}

enum DateText {
    static func dayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "'Tháng' MM/'năm' yyyy"
        return formatter.string(from: date)
    }

    static func compactMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "MM/yyyy"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        "\(dayMonth(date)) · \(time(date))"
    }
}

struct CategoryIcon: View {
    let category: FinanceCategory
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(category.tint)
            .frame(width: size, height: size)
            .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceStyle.purple)
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(FinanceStyle.purple)
                .frame(width: 72, height: 72)
                .background(FinanceStyle.purpleLight, in: Circle())
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(FinanceStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
    }
}


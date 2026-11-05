import SwiftUI

enum FinanceStyle {
    static let background = Color(hex: 0xF5F6FA)
    static let ink = Color(hex: 0x1E2235)
    static let muted = Color(hex: 0x85899B)
    static let purple = Color(hex: 0x665DF2)
    static let purpleLight = Color(hex: 0xEFEDFF)
    static let green = Color(hex: 0x22A879)
    static let greenLight = Color(hex: 0xE6F7F0)
    static let red = Color(hex: 0xE66A74)
    static let redLight = Color(hex: 0xFFF0F0)
    static let line = Color(hex: 0xEBEDF3)
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
        switch self {
        case .food: return Color(hex: 0xF09A56)
        case .transport: return Color(hex: 0x5187E8)
        case .shopping: return Color(hex: 0xBD73D7)
        case .housing: return Color(hex: 0xEA7284)
        case .health: return Color(hex: 0x36AFA1)
        case .entertainment: return Color(hex: 0xE1A53C)
        case .education: return Color(hex: 0x5D9F77)
        case .bills: return Color(hex: 0x7F7BE5)
        case .salary: return FinanceStyle.green
        case .bonus: return Color(hex: 0xE1A53C)
        case .investment: return Color(hex: 0x5187E8)
        case .gift: return Color(hex: 0xE66A94)
        case .other: return Color(hex: 0x9297A8)
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
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    static func compactMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "M/yy"
        return formatter.string(from: date)
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

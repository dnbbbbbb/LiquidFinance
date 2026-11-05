import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var store: FinanceStore
    @State private var openingBalanceText = ""
    @State private var showingResetConfirmation = false
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingExportError = false

    private struct CurrencyOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    private let currencies = [
        CurrencyOption(code: "VND", name: "Việt Nam đồng"),
        CurrencyOption(code: "USD", name: "Đô la Mỹ"),
        CurrencyOption(code: "EUR", name: "Euro"),
        CurrencyOption(code: "JPY", name: "Yên Nhật"),
        CurrencyOption(code: "GBP", name: "Bảng Anh")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                balanceSection
                preferencesSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 110)
        }
        .background(FinanceStyle.background.ignoresSafeArea())
        .onAppear { openingBalanceText = String(store.preferences.openingBalance) }
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Xóa toàn bộ dữ liệu?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Xóa toàn bộ dữ liệu", role: .destructive) {
                store.clearAllData()
                openingBalanceText = "0"
            }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả giao dịch, ngân sách và cài đặt trên iPhone này sẽ bị xóa.")
        }
        .alert("Không thể xuất tệp", isPresented: $showingExportError) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text("Hãy thử lại sau.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CÁ NHÂN HÓA TRẢI NGHIỆM")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FinanceStyle.purple)
            Text("Cài đặt")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Tùy chỉnh cách bạn theo dõi tài chính.")
                .font(.system(size: 14))
                .foregroundStyle(FinanceStyle.muted)
        }
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Số dư ban đầu", systemImage: "banknote")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
            Text("Nhập số dư hiện có để tổng quan phản ánh đúng tình hình của bạn.")
                .font(.system(size: 13))
                .foregroundStyle(FinanceStyle.muted)
            HStack(spacing: 10) {
                TextField("0", text: $openingBalanceText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .accessibilityLabel("Số dư ban đầu")
                Text(store.preferences.currencyCode)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FinanceStyle.muted)
                Button("Lưu") { saveOpeningBalance() }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(FinanceStyle.purple, in: Capsule())
            }
            .padding(12)
            .background(FinanceStyle.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Tùy chọn", systemImage: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
                .padding(.bottom, 12)
            HStack {
                Label("Đơn vị tiền", systemImage: "dollarsign.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FinanceStyle.ink)
                Spacer()
                Picker("Đơn vị tiền", selection: Binding(
                    get: { store.preferences.currencyCode },
                    set: { value in store.updatePreferences { $0.currencyCode = value } }
                )) {
                    ForEach(currencies) { currency in
                        Text("\(currency.code) · \(currency.name)").tag(currency.code)
                    }
                }
                .labelsHidden()
                .tint(FinanceStyle.purple)
                .fixedSize()
            }
            Divider().overlay(FinanceStyle.line).padding(.vertical, 8)
            Toggle(isOn: Binding(
                get: { store.preferences.hidesBalance },
                set: { value in store.updatePreferences { $0.hidesBalance = value } }
            )) {
                Label("Ẩn số dư trên màn hình", systemImage: "eye.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FinanceStyle.ink)
            }
            .tint(FinanceStyle.purple)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("Đổi đơn vị tiền không quy đổi các số tiền đã nhập.")
                .font(.system(size: 11))
                .foregroundStyle(FinanceStyle.muted)
                .padding(.leading, 17)
                .offset(y: 23)
        }
        .padding(.bottom, 22)
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dữ liệu của bạn", systemImage: "externaldrive")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FinanceStyle.ink)
            Button(action: exportCSV) {
                settingsActionRow(icon: "square.and.arrow.up", title: "Xuất giao dịch dạng CSV", color: FinanceStyle.purple)
            }
            .buttonStyle(.plain)
            Divider().overlay(FinanceStyle.line)
            Button { showingResetConfirmation = true } label: {
                settingsActionRow(icon: "trash", title: "Xóa toàn bộ dữ liệu", color: FinanceStyle.red)
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func settingsActionRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(FinanceStyle.muted)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var aboutSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(FinanceStyle.green)
            Text("Liquid Finance")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(FinanceStyle.ink)
            Text("Đơn giản, riêng tư, dành cho bạn · Phiên bản 1.0")
                .font(.system(size: 12))
                .foregroundStyle(FinanceStyle.muted)
            Text("Mọi dữ liệu được lưu trên thiết bị và không cần tạo tài khoản.")
                .font(.system(size: 12))
                .foregroundStyle(FinanceStyle.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func saveOpeningBalance() {
        let value = openingBalanceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(value) else { return }
        store.updatePreferences { $0.openingBalance = amount }
    }

    private func exportCSV() {
        guard let url = CSVExporter.createFile(transactions: store.transactions) else {
            showingExportError = true
            return
        }
        exportURL = url
        showingShareSheet = true
    }
}

private enum CSVExporter {
    static func createFile(transactions: [FinanceTransaction]) -> URL? {
        let header = ["Ngày", "Loại", "Tên", "Danh mục", "Số tiền", "Tài khoản", "Ghi chú"]
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                ISO8601DateFormatter().string(from: transaction.date),
                transaction.type.title,
                transaction.title,
                transaction.category.rawValue,
                String(transaction.amount),
                transaction.account,
                transaction.note
            ]
        }
        let csv = ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidFinance-GiaoDich.csv")
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

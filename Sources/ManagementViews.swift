import SwiftUI

struct CategoryManagementView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: CategorySheet?

    private enum CategorySheet: Identifiable {
        case add
        case edit(FinanceCategory)
        var id: String { switch self { case .add: return "add"; case .edit(let item): return item.id } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(TransactionType.allCases) { type in
                    Section(type == .expense ? "Chi tiêu" : "Thu nhập") {
                        ForEach(store.categories(for: type).filter { $0.parentID == nil }) { parent in
                            VStack(alignment: .leading, spacing: 0) {
                                categoryRow(parent)
                                ForEach(store.categories(for: type).filter { $0.parentID == parent.id }) { child in
                                    HStack(spacing: 9) {
                                        Text("↳").foregroundStyle(FinanceStyle.muted)
                                        categoryRow(child)
                                    }
                                    .padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinanceStyle.background)
            .navigationTitle("Danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { sheet = .add } label: { Image(systemName: "plus") } }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .add: CategoryEditorView(store: store)
                case .edit(let category): CategoryEditorView(store: store, category: category)
                }
            }
        }
    }

    private func categoryRow(_ category: FinanceCategory) -> some View {
        HStack {
            CategoryIcon(category: category, size: 34)
            Text(category.name).font(.system(size: 14, weight: .medium))
            Spacer()
            Button { sheet = .edit(category) } label: { Image(systemName: "pencil").foregroundStyle(FinanceStyle.muted) }
                .buttonStyle(.plain)
            Button(role: .destructive) { store.deleteCategory(id: category.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).disabled(category.id == FinanceCategory.other.id || category.id == FinanceCategory.incomeOther.id)
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryEditorView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let category: FinanceCategory?
    @State private var name: String
    @State private var type: TransactionType
    @State private var parentID: String
    @State private var error = false

    init(store: FinanceStore, category: FinanceCategory? = nil) {
        self.store = store; self.category = category
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.type ?? .expense)
        _parentID = State(initialValue: category?.parentID ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên danh mục", text: $name)
                    Picker("Loại", selection: $type) { ForEach(TransactionType.allCases) { Text($0.title).tag($0) } }
                    Picker("Nhóm cha", selection: $parentID) {
                        Text("Không có · danh mục cha").tag("")
                        ForEach(store.categories(for: type).filter { $0.parentID == nil && $0.id != category?.id }) { item in Text(item.name).tag(item.id) }
                    }
                }
                Text("Danh mục con sẽ được hiển thị bên trong nhóm cha.").font(.system(size: 13)).foregroundStyle(FinanceStyle.muted)
            }
            .navigationTitle(category == nil ? "Danh mục mới" : "Sửa danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
            .alert("Nhập tên danh mục", isPresented: $error) { Button("Đã hiểu", role: .cancel) { } }
            .onChange(of: type) { _ in parentID = "" }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { error = true; return }
        store.saveCategory(FinanceCategory(
            id: category?.id ?? UUID().uuidString,
            name: cleanName,
            type: type,
            parentID: parentID.isEmpty ? nil : parentID,
            symbol: category?.symbol ?? "circle.grid.2x2.fill"
        ))
        dismiss()
    }
}

struct WalletManagementView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: WalletSheet?

    private enum WalletSheet: Identifiable {
        case add
        case edit(FinanceWallet)
        var id: String { switch self { case .add: return "add"; case .edit(let item): return item.id.uuidString } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.wallets) { wallet in
                    HStack(spacing: 12) {
                        Image(systemName: wallet.kind == "Ví tiền mặt" ? "banknote" : "creditcard.fill")
                            .foregroundStyle(FinanceStyle.purple).frame(width: 38, height: 38)
                            .background(FinanceStyle.purpleLight, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallet.name).font(.system(size: 15, weight: .semibold))
                            Text(MoneyText.string(store.balance(for: wallet), currencyCode: store.preferences.currencyCode))
                                .font(.system(size: 13)).foregroundStyle(FinanceStyle.muted)
                        }
                        Spacer()
                        Button { sheet = .edit(wallet) } label: { Image(systemName: "pencil").foregroundStyle(FinanceStyle.muted) }
                            .buttonStyle(.plain)
                        Button(role: .destructive) { store.deleteWallet(id: wallet.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).disabled(store.wallets.count <= 1)
                    }
                    .padding(.vertical, 5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinanceStyle.background)
            .navigationTitle("Ví của tôi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { sheet = .add } label: { Image(systemName: "plus") } }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .add: WalletEditorView(store: store)
                case .edit(let wallet): WalletEditorView(store: store, wallet: wallet)
                }
            }
        }
    }
}

private struct WalletEditorView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let wallet: FinanceWallet?
    @State private var name: String
    @State private var kind: String
    @State private var amount: String

    init(store: FinanceStore, wallet: FinanceWallet? = nil) {
        self.store = store; self.wallet = wallet
        _name = State(initialValue: wallet?.name ?? "")
        _kind = State(initialValue: wallet?.kind ?? "Ví tiền mặt")
        _amount = State(initialValue: String(wallet?.openingBalance ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên ví", text: $name)
                Picker("Loại ví", selection: $kind) {
                    Text("Ví tiền mặt").tag("Ví tiền mặt")
                    Text("Tài khoản ngân hàng").tag("Tài khoản ngân hàng")
                    Text("Thẻ tín dụng").tag("Thẻ tín dụng")
                    Text("Ví điện tử").tag("Ví điện tử")
                }
                HStack {
                    TextField("Số dư ban đầu", text: $amount).keyboardType(.decimalPad)
                    Text(store.preferences.currencyCode)
                }
            }
            .navigationTitle(wallet == nil ? "Ví mới" : "Sửa ví")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let parsed = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        store.saveWallet(FinanceWallet(id: wallet?.id ?? UUID(), name: cleanName, kind: kind, openingBalance: parsed))
        dismiss()
    }
}


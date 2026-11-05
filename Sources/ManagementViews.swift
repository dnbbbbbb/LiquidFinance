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
    @State private var symbol: String
    @State private var colorHex: UInt32?
    @State private var error = false

    init(store: FinanceStore, category: FinanceCategory? = nil) {
        self.store = store; self.category = category
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.type ?? .expense)
        _parentID = State(initialValue: category?.parentID ?? "")
        _symbol = State(initialValue: category?.symbol ?? "circle.grid.2x2.fill")
        _colorHex = State(initialValue: category?.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên danh mục", text: $name)
                    Picker("Loại", selection: $type) { ForEach(TransactionType.allCases) { Text($0.title).tag($0) } }
                    Picker("Nhóm cha", selection: $parentID) {
                        Text("Không có").tag("")
                        ForEach(store.categories(for: type).filter { $0.parentID == nil && $0.id != category?.id }) { item in Text(item.name).tag(item.id) }
                    }
                }
                Section("Biểu tượng") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Self.symbols + Self.moreSymbols, id: \.self) { item in
                            Button { symbol = item } label: {
                                Image(systemName: item)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(symbol == item ? .white : FinanceStyle.purple)
                                    .frame(width: 42, height: 42)
                                    .background(symbol == item ? FinanceStyle.purple : FinanceStyle.purpleLight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Màu sắc") {
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button { colorHex = nil } label: {
                            Image(systemName: colorHex == nil ? "checkmark" : "circle")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(colorHex == nil ? .white : FinanceStyle.muted)
                                .frame(width: 36, height: 36)
                                .background(colorHex == nil ? FinanceStyle.purple : FinanceStyle.background, in: Circle())
                        }
                        .buttonStyle(.plain)
                        ForEach(Self.colors, id: \.self) { color in
                            Button { colorHex = color } label: {
                                Image(systemName: colorHex == color ? "checkmark" : "circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(colorHex == color ? .white : Color(hex: color))
                                    .frame(width: 36, height: 36)
                                    .background(Color(hex: color).opacity(colorHex == color ? 1 : 0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
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
        .background(KeyboardDismissOnTap())
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
            symbol: symbol,
            colorHex: colorHex
        ))
        dismiss()
    }

    private static let symbols = ["circle.grid.2x2.fill", "fork.knife", "cart.fill", "car.fill", "house.fill", "bolt.fill", "heart.fill", "cross.case.fill", "book.closed.fill", "gamecontroller.fill", "gift.fill", "briefcase.fill", "bag.fill", "phone.fill", "airplane", "pawprint.fill", "music.note", "creditcard.fill", "banknote.fill", "ellipsis.circle.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "tram.fill", "bicycle", "bus.fill", "fuelpump.fill", "wifi", "lightbulb.fill", "drop.fill", "leaf.fill", "dumbbell.fill", "figure.run", "stethoscope", "graduationcap.fill", "laptopcomputer", "wrench.and.screwdriver.fill", "building.2.fill", "bed.double.fill", "dog.fill", "cat.fill", "ticket.fill", " 영화.fill", "camera.fill", "shippingbox.fill", "arrow.left.arrow.right.circle.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill", "wallet.bifold.fill"]
    private static let moreSymbols = ["film.fill", "basket.fill", "cloud.fill", "sun.max.fill", "moon.fill", "car.rear.fill", "scooter", "pills.fill", "tv.fill", "headphones", "sportscourt.fill", "tent.fill", "tree.fill", "hammer.fill", "paintbrush.pointed.fill", "archivebox.fill", "person.fill", "person.2.fill", "party.popper.fill", "percent", "chart.pie.fill", "bitcoinsign.circle.fill", "house.and.flag.fill", "flame.fill", "snowflake", "carrot.fill", "fish.fill", "wineglass.fill", "fork.knife.circle.fill", "pencil.and.outline", "scissors", "printer.fill", "keyboard.fill", "desktopcomputer", "airpodspro", "record.circle.fill", "theatermasks.fill", "flag.fill", "medal.fill", "soccerball", "figure.walk", "bicycle.circle.fill"]
    private static let colors: [UInt32] = [0x665DF2, 0xF09A56, 0x5187E8, 0xBD73D7, 0xEA7284, 0x36AFA1, 0xE1A53C, 0x22A879, 0xE05D44, 0x4D6B50, 0xD64F91, 0x3E9CBE, 0xA87D32, 0x7257A8, 0x607D8B, 0xC0392B, 0x16A085, 0x2C3E50, 0xEF6C00, 0x00897B, 0x5C6BC0, 0x8E24AA, 0x3949AB, 0x7CB342, 0xF4511E, 0x039BE5, 0x6D4C41, 0x546E7A, 0xD81B60, 0x00ACC1]
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

struct RecurringManagementView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingRule: RecurringRule?

    var body: some View {
        NavigationStack {
            List {
                if store.recurringRules.isEmpty {
                    Text("Giao dịch định kỳ sẽ xuất hiện tại đây khi bạn bật Lặp lại trong biểu mẫu giao dịch.")
                        .foregroundStyle(FinanceStyle.muted)
                }
                ForEach(store.recurringRules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title).font(.system(size: 15, weight: .semibold))
                                Text(scheduleText(for: rule))
                                    .font(.system(size: 12)).foregroundStyle(FinanceStyle.muted)
                            }
                            Spacer()
                            Text(MoneyText.string(rule.amount, currencyCode: store.preferences.currencyCode))
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(FinanceStyle.ink)
                            Button { editingRule = rule } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 21)).foregroundStyle(FinanceStyle.purple)
                            }
                            .buttonStyle(.plain)
                        }
                        Toggle("Đang hoạt động", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { value in var updated = rule; updated.isEnabled = value; store.setRecurringRule(updated) }
                        )).tint(FinanceStyle.purple)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.deleteRecurringRule(id: rule.id) } label: { Label("Xóa", systemImage: "trash") }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(FinanceStyle.background)
            .navigationTitle("Giao dịch định kỳ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
            .sheet(item: $editingRule) { rule in
                RecurringRuleEditor(store: store, rule: rule)
            }
        }
    }

    private func scheduleText(for rule: RecurringRule) -> String {
        let weekday = rule.weekday.map { " · \(FinanceDate.weekdayTitle($0))" } ?? ""
        return "\(rule.frequency.title)\(weekday) · kế tiếp \(DateText.dateTime(rule.nextDate))"
    }
}

private struct RecurringRuleEditor: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let rule: RecurringRule
    @State private var frequency: RecurrenceFrequency
    @State private var weekday: Int
    @State private var nextDate: Date

    init(store: FinanceStore, rule: RecurringRule) {
        self.store = store
        self.rule = rule
        _frequency = State(initialValue: rule.frequency)
        _weekday = State(initialValue: rule.weekday ?? Calendar.current.component(.weekday, from: rule.nextDate))
        _nextDate = State(initialValue: rule.nextDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao dịch") {
                    Text(rule.title)
                    Text(MoneyText.string(rule.amount, currencyCode: store.preferences.currencyCode))
                        .foregroundStyle(FinanceStyle.muted)
                }
                Section("Lịch lặp") {
                    Picker("Chu kỳ", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    if frequency == .weekly || frequency == .biweekly {
                        Picker("Ngày lặp", selection: $weekday) {
                            ForEach(1...7, id: \.self) { value in Text(FinanceDate.weekdayTitle(value)).tag(value) }
                        }
                    }
                    DatePicker("Lần tiếp theo", selection: $nextDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Sửa lịch định kỳ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        var updated = rule
                        updated.frequency = frequency
                        updated.weekday = (frequency == .weekly || frequency == .biweekly) ? weekday : nil
                        updated.nextDate = nextDate
                        store.setRecurringRule(updated)
                        dismiss()
                    }
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
        _amount = State(initialValue: wallet.map { $0.openingBalance == 0 ? "" : AmountInput.format($0.openingBalance) } ?? "")
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
                    AmountTextField(text: $amount, placeholder: "0", fontSize: 18).frame(height: 30)
                    Text(store.preferences.currencyCode)
                }
            }
            .navigationTitle(wallet == nil ? "Ví mới" : "Sửa ví")
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
        }
        .background(KeyboardDismissOnTap())
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let parsed = AmountInput.parse(amount) ?? 0
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        store.saveWallet(FinanceWallet(id: wallet?.id ?? UUID(), name: cleanName, kind: kind, openingBalance: parsed))
        dismiss()
    }
}


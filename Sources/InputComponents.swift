import SwiftUI
import UIKit

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard context.coordinator.gesture == nil, let host = view.superview else { return }
            let gesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
            gesture.cancelsTouchesInView = false
            gesture.delegate = context.coordinator
            host.addGestureRecognizer(gesture)
            context.coordinator.gesture = gesture
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var gesture: UITapGestureRecognizer?

        @objc func dismissKeyboard() { Keyboard.dismiss() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

enum AmountInput {
    static func parse(_ value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

struct AmountTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "0"
    var fontSize: CGFloat = 22

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .decimalPad
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = .label
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.55)])
        field.delegate = context.coordinator
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Xong", style: .done, target: context.coordinator, action: #selector(Coordinator.done))
        ]
        field.inputAccessoryView = toolbar
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.text = text
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.55)])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountTextField
        init(_ parent: AmountTextField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let unformatted = current.replacingOccurrences(of: ".", with: "")
            let cleanStart = current[..<swiftRange.lowerBound].filter { $0 != "." }.count
            let selectedLength = current[swiftRange].filter { $0 != "." }.count
            let cleanRange = Range(NSRange(location: cleanStart, length: selectedLength), in: unformatted)
            guard let cleanRange else { return false }
            var edited = unformatted.replacingCharacters(in: cleanRange, with: string)
            edited = String(edited.filter { $0.isNumber || $0 == "," })
            let pieces = edited.split(separator: ",", omittingEmptySubsequences: false)
            let integer = String(pieces.first ?? "")
            let grouped = group(integer)
            let result = pieces.count > 1 ? grouped + "," + pieces.dropFirst().joined() : grouped
            parent.text = result
            textField.text = result
            let cursorCharacters = current[..<swiftRange.lowerBound].filter { $0 != "." }.count
                + string.filter { $0.isNumber || $0 == "," }.count
            if let position = position(after: cursorCharacters, in: result, field: textField) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            return false
        }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        @objc func done() { Keyboard.dismiss() }

        private func group(_ digits: String) -> String {
            let reversed = Array(digits.reversed())
            let chunks = stride(from: 0, to: reversed.count, by: 3).map { index in String(reversed[index..<min(index + 3, reversed.count)].reversed()) }
            return chunks.reversed().joined(separator: ".")
        }

        private func position(after characters: Int, in value: String, field: UITextField) -> UITextPosition? {
            if characters == 0 { return field.beginningOfDocument }
            var count = 0
            var offset = 0
            for character in value {
                offset += String(character).utf16.count
                if character != "." { count += 1 }
                if count >= characters { break }
            }
            return field.position(from: field.beginningOfDocument, offset: offset)
        }
    }
}

struct DateRangeFilterView: View {
    @Binding var isEnabled: Bool
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Lọc theo thời gian", isOn: $isEnabled).tint(FinanceStyle.purple)
            if isEnabled {
                DatePicker("Từ", selection: $start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Đến", selection: $end, displayedComponents: [.date, .hourAndMinute])
                Button("Không giới hạn ngày") { isEnabled = false }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(FinanceStyle.purple)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(15)
        .background(FinanceStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MonthNavigator: View {
    @Binding var month: Date
    @State private var showingPicker = false

    var body: some View {
        HStack(spacing: 14) {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Tháng trước")

            Button { showingPicker = true } label: {
                Label(DateText.monthYear(month), systemImage: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Chọn tháng và năm")

            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Tháng sau")
        }
        .foregroundStyle(FinanceStyle.ink)
        .padding(.horizontal, 5)
        .background(FinanceStyle.card, in: Capsule())
        .sheet(isPresented: $showingPicker) {
            MonthYearPicker(month: $month)
        }
    }

    private func moveMonth(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
    }
}

private struct MonthYearPicker: View {
    @Binding var month: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: Int
    @State private var selectedYear: Int

    init(month: Binding<Date>) {
        _month = month
        let parts = Calendar.current.dateComponents([.month, .year], from: month.wrappedValue)
        _selectedMonth = State(initialValue: parts.month ?? 1)
        _selectedYear = State(initialValue: parts.year ?? Calendar.current.component(.year, from: .now))
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((current - 20)...(current + 20))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tháng", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { value in
                        Text(String(format: "%02d", value)).tag(value)
                    }
                }
                Picker("Năm", selection: $selectedYear) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                Button("Tháng hiện tại") {
                    let now = Date.now
                    selectedMonth = Calendar.current.component(.month, from: now)
                    selectedYear = Calendar.current.component(.year, from: now)
                }
            }
            .navigationTitle("Chọn tháng")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        month = Calendar.current.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? month
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

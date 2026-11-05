import SwiftUI
import UIKit

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
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.text = text
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
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

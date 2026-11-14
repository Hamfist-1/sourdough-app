import SwiftUI
import BakeCore

/// A number typed as text, so anything that depends on it updates on every keystroke.
/// Empty text means nil.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var suffix: String = ""
    var prompt: String = "–"

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(prompt, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .frame(maxWidth: 110)
                if !suffix.isEmpty {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, newText in
            let parsed = Self.parse(newText)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = Self.format(newValue) }
        }
    }

    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return Format.number((value * 100).rounded() / 100)
    }
}

// MARK: - Unit adapters for NumberField

extension Binding where Value == Double? {
    /// A required fraction (0.75) edited as a percent (75). Clearing the field keeps the old value.
    static func percent(_ fraction: Binding<Double>) -> Binding<Double?> {
        Binding(
            get: { fraction.wrappedValue * 100 },
            set: { if let percent = $0 { fraction.wrappedValue = percent / 100 } }
        )
    }

    /// Seconds edited as minutes.
    static func minutes(_ seconds: Binding<TimeInterval?>) -> Binding<Double?> {
        Binding(
            get: { seconds.wrappedValue.map { $0 / 60 } },
            set: { seconds.wrappedValue = $0.map { $0 * 60 } }
        )
    }

    /// Seconds edited as hours.
    static func hours(_ seconds: Binding<TimeInterval?>) -> Binding<Double?> {
        Binding(
            get: { seconds.wrappedValue.map { $0 / 3600 } },
            set: { seconds.wrappedValue = $0.map { $0 * 3600 } }
        )
    }

    /// °C stored, edited in the user's unit.
    static func temperature(_ celsius: Binding<Double?>, unit: TemperatureUnit) -> Binding<Double?> {
        Binding(
            get: { celsius.wrappedValue.map(unit.fromCelsius) },
            set: { celsius.wrappedValue = $0.map(unit.toCelsius) }
        )
    }

    /// A whole number.
    static func whole(_ value: Binding<Int?>) -> Binding<Double?> {
        Binding(
            get: { value.wrappedValue.map(Double.init) },
            set: { value.wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }
}

extension Binding where Value == String {
    /// Optional text, where an empty field means nil.
    static func optional(_ text: Binding<String?>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue ?? "" },
            set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Pickers

/// A picker with a "Not set" option.
struct OptionalPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T?
    let options: [T]
    let label: (T) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Not set").tag(T?.none)
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(T?.some(option))
            }
        }
    }
}

/// A picker for choices with an "Other…" option that asks for the user's own text.
struct ChoicePicker<T: OtherChoice>: View {
    let title: String
    @Binding var selection: T?

    /// The picker sees every "other" as one option.
    private var pickerSelection: Binding<T?> {
        Binding(
            get: { selection.map { $0.isOther ? T.other("") : $0 } },
            set: { newValue in
                if let newValue, newValue.isOther {
                    if selection?.isOther != true { selection = T.other("") }
                } else {
                    selection = newValue
                }
            }
        )
    }

    private var otherText: Binding<String> {
        Binding(
            get: { selection?.otherText ?? "" },
            set: { selection = T.other($0) }
        )
    }

    var body: some View {
        OptionalPicker(
            title: title,
            selection: pickerSelection,
            options: T.standardChoices + [T.other("")],
            label: { $0.isOther ? "Other…" : $0.label }
        )
        if selection?.isOther == true {
            TextField("Describe", text: otherText)
        }
    }
}

// MARK: - Keyboard

extension View {
    /// Adds a Done button above the keyboard (the number pad has no return key) and lets
    /// scrolling dismiss it. Apply once per screen, on the Form or List.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                    .bold()
                }
            }
    }
}

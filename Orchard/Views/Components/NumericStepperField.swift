import SwiftUI

/// A bounded integer input: a numeric text field paired with a stepper. Type a value or nudge
/// it with the arrows; out-of-range entries are clamped to `range`. Used for machine CPUs and
/// memory so the value is always a valid number within the host's capacity.
struct NumericStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
                .onChange(of: value) { _, newValue in
                    let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                    if clamped != newValue { value = clamped }
                }
            if let unit {
                Text(unit).foregroundStyle(.secondary)
            }
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

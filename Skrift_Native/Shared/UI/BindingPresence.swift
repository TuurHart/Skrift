import SwiftUI

/// What `Binding.isPresent` needs from an optional: whether it holds a value, and the
/// empty value to write back on dismiss. Only `Optional` conforms.
protocol OptionalValue {
    var hasValue: Bool { get }
    static var absent: Self { get }
}

extension Optional: OptionalValue {
    var hasValue: Bool { self != nil }
    static var absent: Wrapped? { nil }
}

extension Binding where Value: OptionalValue {
    /// A Bool binding for `.alert` / `.sheet` / `.confirmationDialog(isPresented:)` that is true
    /// while this optional holds a value and clears it when SwiftUI dismisses (C239).
    /// Replaces the hand-written `Binding(get: { x != nil }, set: { if !$0 { x = nil } })`.
    var isPresent: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.hasValue },
            set: { if !$0 { wrappedValue = Value.absent } }
        )
    }
}

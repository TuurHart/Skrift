import SwiftUI

extension AppShortcuts.Chord {
    var swiftUIKey: KeyEquivalent { KeyEquivalent(Character(key)) }
    var swiftUIModifiers: EventModifiers {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        return m
    }
}

extension View {
    /// `.keyboardShortcut` fed from the shared table.
    func keyboardShortcut(_ chord: AppShortcuts.Chord) -> some View {
        keyboardShortcut(chord.swiftUIKey, modifiers: chord.swiftUIModifiers)
    }
}

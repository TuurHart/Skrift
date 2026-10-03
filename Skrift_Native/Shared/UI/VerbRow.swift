import SwiftUI

// Q171 (C239/C240, parity audit list-sidebar-18/-21/-08, note-header-09): the list header's
// verb buttons, the note bar's panel toggle and the context chip were hand copies in the two
// apps. One view each here; the per-app part is a style struct of colours and sizes, the
// `NoteCardStyle` pattern. No `#if os()` in this file. The Button around a label stays in each
// app (the actions, shortcuts, tooltips and test ids differ); only what it DRAWS is shared.

/// Colours + sizes for the Import / Record / New-note labels. The phone's row is tap-sized
/// (44pt, continuous corners, skElev); the Mac's is intrinsic height + 7pt padding.
struct VerbButtonStyle {
    var text: Color
    var record: Color
    var fill: Color
    /// Minimum height of a wide verb (the phone's HIG tap floor); nil = intrinsic.
    var minHeight: CGFloat? = nil
    var verticalPadding: CGFloat = 0
    /// Width of the typed-note chip (phone 44 = square against its 44 height, Mac 34).
    var newNoteWidth: CGFloat
    /// Size of the + glyph on Import.
    var importIconSize: CGFloat
    var continuousCorners: Bool

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: continuousCorners ? .continuous : .circular)
    }
}

/// "+ Import" — the verb that brings external material in.
struct ImportVerbLabel: View {
    let style: VerbButtonStyle
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: style.importIconSize, weight: .semibold))
            Text(SharedCopy.importVerb).lineLimit(1)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, minHeight: style.minHeight)
        .padding(.vertical, style.verticalPadding)
        .background(style.fill, in: style.shape)
    }
}

/// The red dot + "Record".
struct RecordVerbLabel: View {
    let style: VerbButtonStyle
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(style.record).frame(width: 9, height: 9)
            Text(SharedCopy.recordVerb).lineLimit(1)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(style.record)
        .frame(maxWidth: .infinity, minHeight: style.minHeight)
        .padding(.vertical, style.verticalPadding)
        .background(style.fill, in: style.shape)
    }
}

/// The typed-note chip: the system compose glyph, fixed width.
struct NewNoteVerbLabel: View {
    let style: VerbButtonStyle
    var body: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(style.text)
            .frame(width: style.newNoteWidth)
            .frame(minHeight: style.minHeight)
            .padding(.vertical, style.verticalPadding)
            .background(style.fill, in: style.shape)
    }
}

// MARK: - Bar glass + panel toggle

/// The containment chip behind every note-bar control (the iPad's `barGlass`, the Mac's mirror
/// of it): quiet fill + hairline, or an accent-soft fill while its state is active.
struct BarGlassStyle {
    var onFill: Color
    var offFill: Color
    var border: Color
}

extension View {
    func barGlass(on: Bool = false, in shape: some InsettableShape = Circle(), style: BarGlassStyle) -> some View {
        background(on ? style.onFill : style.offFill, in: shape)
            .overlay(on ? nil : shape.strokeBorder(style.border, lineWidth: 0.5))
    }
}

struct PanelToggleStyle {
    var glass: BarGlassStyle
    var onText: Color
    var offText: Color
}

/// The note bar's ◧ panel toggle chip (signed mock ipad-note-chrome-belongs.html): a plain
/// system sidebar glyph in a glass circle, accent-soft while the list is open.
struct PanelToggleLabel: View {
    let icon: String
    let on: Bool
    let style: PanelToggleStyle
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(on ? style.onText : style.offText)
            .frame(width: 30, height: 30)
            .barGlass(on: on, style: style.glass)
    }
}

// MARK: - Context chip

/// One fact about the note as a small pill, icon + one line of text (11pt, 7pt radius).
/// The phone's `ContextChip` and the Mac's `MacContextChip` both draw this.
struct ContextChipStyle {
    var text: Color
    var fill: Color
}

struct ContextChipView: View {
    let text: String
    var systemImage: String?
    let style: ContextChipStyle
    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10)) }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11))
        .foregroundStyle(style.text)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(style.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

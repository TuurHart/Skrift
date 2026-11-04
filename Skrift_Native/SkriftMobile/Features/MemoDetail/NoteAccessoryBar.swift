import UIKit
import SwiftUI

/// The editor's keyboard accessory — a floating Skrift pill (same glass language
/// as the player bar), NOT the flat system strip. v2 = variant B of the
/// signed-off `mocks/accessory-bar-v2.html` (2026-07-07), amended by device
/// round 2 same day: NO ⋯ overflow while every verb still fits — find rides
/// inline. Revisit overflow-vs-scroll only when scan/markup verbs arrive.
final class NoteAccessoryBar: UIView {
    /// `.editor` = the note editor's bar per the signed Q542 mock ("One bar at the bottom", Q544):
    /// Aa · checklist · photo · note link · | · undo · redo · Done, each tap target 44 wide and the
    /// bar's full 54 tall while the pill stays 40 tall; Find lives in the ⋯ menu.
    /// `.quickNote` = the quick-note screen's bar, unchanged (undo · redo · find · Done).
    enum Layout { case quickNote, editor }

    var onFormat: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onFind: (() -> Void)?
    var onPhoto: (() -> Void)?
    var onChecklist: (() -> Void)?
    var onMemoLink: (() -> Void)?
    var onDone: (() -> Void)?

    /// Tap target of one button: the editor bar gives each the bar's full height (Q544); the
    /// quick-note bar keeps its 33 x 30.
    private struct Metrics {
        let width: CGFloat, height: CGFloat
        /// Space between the tap target's edge and the painted highlight (the lit Aa / checklist).
        let fillInsets: NSDirectionalEdgeInsets
        static let editor = Metrics(width: 44, height: 54,
                                    fillInsets: .init(top: 12, leading: 4, bottom: 12, trailing: 4))
        static let quickNote = Metrics(width: 33, height: 30, fillInsets: .zero)
    }

    private let undoButton: UIButton
    private let redoButton: UIButton
    private let checklistButton: UIButton
    private let photoButton: UIButton
    private let linkButton: UIButton
    private let findButton: UIButton
    private let doneButton: UIButton
    private let formatButton: UIButton

    init(layout: Layout = .quickNote) {
        let m: Metrics = layout == .editor ? .editor : .quickNote
        undoButton = NoteAccessoryBar.iconButton("arrow.uturn.backward", id: "accessory-undo", m)
        redoButton = NoteAccessoryBar.iconButton("arrow.uturn.forward", id: "accessory-redo", m)
        checklistButton = NoteAccessoryBar.iconButton("checklist", id: "accessory-checklist", m)
        photoButton = NoteAccessoryBar.iconButton("camera", id: "accessory-photo", m)
        linkButton = NoteAccessoryBar.iconButton("arrow.right", id: "accessory-link", m)
        findButton = NoteAccessoryBar.iconButton("magnifyingglass", id: "accessory-find", m)
        doneButton = UIButton(configuration: .plain())
        formatButton = UIButton(configuration: .plain())
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 54))
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear

        let pill = UIView()
        pill.backgroundColor = UIColor(Color.skSurface).withAlphaComponent(0.94)
        pill.layer.cornerRadius = 15
        pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth = 0.5
        pill.layer.borderColor = UIColor.white.withAlphaComponent(0.13).cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.35
        pill.layer.shadowRadius = 11
        pill.layer.shadowOffset = CGSize(width: 0, height: 6)
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true

        // Done: the painted pill is 30 tall; the editor's tap target is the full row height.
        var done = UIButton.Configuration.plain()
        done.title = "Done"
        done.baseForegroundColor = UIColor(Color.skAccent)
        done.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var a = $0; a.font = .systemFont(ofSize: 13.5, weight: .semibold); return a
        }
        done.background.backgroundColor = UIColor(Color.skAccentSoft)
        done.background.cornerRadius = 9
        if layout == .editor {
            done.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            done.background.backgroundInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        } else {
            done.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        }
        doneButton.configuration = done
        doneButton.accessibilityIdentifier = "accessory-done"
        if layout == .editor { doneButton.heightAnchor.constraint(equalToConstant: m.height).isActive = true }

        undoButton.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .touchUpInside)
        redoButton.addAction(UIAction { [weak self] _ in self?.onRedo?() }, for: .touchUpInside)
        checklistButton.addAction(UIAction { [weak self] _ in self?.onChecklist?() }, for: .touchUpInside)
        photoButton.addAction(UIAction { [weak self] _ in self?.onPhoto?() }, for: .touchUpInside)
        linkButton.addAction(UIAction { [weak self] _ in self?.onMemoLink?() }, for: .touchUpInside)
        findButton.addAction(UIAction { [weak self] _ in self?.onFind?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        var aa = UIButton.Configuration.plain()
        aa.title = "Aa"
        aa.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var a = $0; a.font = .systemFont(ofSize: 16, weight: .semibold); return a
        }
        aa.contentInsets = .zero
        aa.background.cornerRadius = 8
        aa.background.backgroundInsets = m.fillInsets
        formatButton.configuration = aa
        formatButton.tintColor = UIColor(Color.skTextDim)
        formatButton.accessibilityIdentifier = "accessory-format"
        formatButton.accessibilityLabel = "Format"
        formatButton.widthAnchor.constraint(equalToConstant: m.width).isActive = true
        formatButton.heightAnchor.constraint(equalToConstant: m.height).isActive = true
        formatButton.addAction(UIAction { [weak self] _ in self?.onFormat?() }, for: .touchUpInside)

        let items: [UIView]
        switch layout {
        case .editor:
            items = [formatButton, checklistButton, photoButton, linkButton, divider,
                     undoButton, redoButton, UIView(), doneButton]
        case .quickNote:
            items = [undoButton, redoButton, divider, checklistButton, photoButton, linkButton, findButton,
                     UIView(), doneButton]
        }
        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.alignment = .center
        // The editor row is six 44 pt buttons, a divider and Done with no gaps between the
        // buttons, so it fits the 356 pt inside an iPhone 13's bar with room over (mock Q542).
        stack.spacing = layout == .editor ? 0 : 2
        if layout == .quickNote {
            stack.setCustomSpacing(7, after: redoButton)
            stack.setCustomSpacing(7, after: divider)
        } else {
            stack.setCustomSpacing(4, after: linkButton)
            stack.setCustomSpacing(4, after: divider)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The editor's row sits on the bar, not inside the 40 pt pill: a tap target taller than
        // its parent loses every touch outside the parent's bounds.
        addSubview(stack)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: layout == .editor ? -7 : -8),
            pill.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// BUGS §3 (build 172, quick note): the accessory bar disappeared mid-
    /// typing. It was sized only by its initial `frame` (width 0) plus
    /// `autoresizingMask` — no Auto Layout intrinsic size of its own. A
    /// keyboard/accessory host that runs its OWN layout pass concurrently
    /// with a SwiftUI-driven layout invalidation (here: the toolbar's
    /// add-recording/⋯ buttons fading in on the first keystroke, right as
    /// the accessory host relayouts) can read that as "wants zero size" and
    /// collapse it. An explicit intrinsic size makes it self-describing
    /// regardless of which layout system asks.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 54)
    }

    /// Reflect the text view's state: the undo stack, and whether the caret
    /// sits in a checklist line (the ☑ lights up — it will REMOVE the box).
    func refresh(canUndo: Bool, canRedo: Bool, inChecklist: Bool = false) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        checklistButton.tintColor = inChecklist
            ? UIColor(Color.skAccent) : UIColor(Color.skTextDim)
        checklistButton.configuration?.background.backgroundColor = inChecklist
            ? UIColor(Color.skAccentSoft) : .clear
    }

    /// Light the Aa button while the Format panel replaces the keyboard.
    func setFormatOpen(_ open: Bool) {
        formatButton.tintColor = UIColor(open ? Color.skAccent : Color.skTextDim)
        formatButton.configuration?.background.backgroundColor = open ? UIColor(Color.skAccentSoft) : .clear
    }

    private static func iconButton(_ symbol: String, id: String, _ m: Metrics) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.5, weight: .medium))
        c.contentInsets = .zero
        c.background.cornerRadius = 8
        c.background.backgroundInsets = m.fillInsets
        let b = UIButton(configuration: c)
        b.tintColor = UIColor(Color.skTextDim)
        b.accessibilityIdentifier = id
        b.widthAnchor.constraint(equalToConstant: m.width).isActive = true
        b.heightAnchor.constraint(equalToConstant: m.height).isActive = true
        return b
    }
}

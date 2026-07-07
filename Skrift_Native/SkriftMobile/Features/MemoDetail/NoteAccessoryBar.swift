import UIKit
import SwiftUI

/// The editor's keyboard accessory — a floating Skrift pill (same glass language
/// as the player bar), NOT the flat system strip. v2 = variant B of the
/// signed-off `mocks/accessory-bar-v2.html` (2026-07-07), amended by device
/// round 2 same day: NO ⋯ overflow while every verb still fits — find rides
/// inline. Revisit overflow-vs-scroll only when scan/markup verbs arrive.
final class NoteAccessoryBar: UIView {
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onFind: (() -> Void)?
    var onPhoto: (() -> Void)?
    var onChecklist: (() -> Void)?
    var onMemoLink: (() -> Void)?
    var onDone: (() -> Void)?

    private let undoButton = NoteAccessoryBar.iconButton("arrow.uturn.backward", id: "accessory-undo")
    private let redoButton = NoteAccessoryBar.iconButton("arrow.uturn.forward", id: "accessory-redo")
    private let checklistButton = NoteAccessoryBar.iconButton("checklist", id: "accessory-checklist")
    private let photoButton = NoteAccessoryBar.iconButton("camera", id: "accessory-photo")
    private let linkButton = NoteAccessoryBar.iconButton("arrow.right", id: "accessory-link")
    private let findButton = NoteAccessoryBar.iconButton("magnifyingglass", id: "accessory-find")
    private let doneButton = UIButton(type: .system)

    init() {
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

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        doneButton.setTitleColor(UIColor(Color.skAccent), for: .normal)
        doneButton.backgroundColor = UIColor(Color.skAccentSoft)
        doneButton.layer.cornerRadius = 9
        doneButton.layer.cornerCurve = .continuous
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        doneButton.accessibilityIdentifier = "accessory-done"

        undoButton.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .touchUpInside)
        redoButton.addAction(UIAction { [weak self] _ in self?.onRedo?() }, for: .touchUpInside)
        checklistButton.addAction(UIAction { [weak self] _ in self?.onChecklist?() }, for: .touchUpInside)
        photoButton.addAction(UIAction { [weak self] _ in self?.onPhoto?() }, for: .touchUpInside)
        linkButton.addAction(UIAction { [weak self] _ in self?.onMemoLink?() }, for: .touchUpInside)
        findButton.addAction(UIAction { [weak self] _ in self?.onFind?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [undoButton, redoButton, divider,
                                                   checklistButton, photoButton, linkButton, findButton,
                                                   UIView(), doneButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.setCustomSpacing(7, after: redoButton)
        stack.setCustomSpacing(7, after: divider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            pill.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Reflect the text view's state: the undo stack, and whether the caret
    /// sits in a checklist line (the ☑ lights up — it will REMOVE the box).
    func refresh(canUndo: Bool, canRedo: Bool, inChecklist: Bool = false) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        checklistButton.tintColor = inChecklist
            ? UIColor(Color.skAccent) : UIColor(Color.skTextDim)
        checklistButton.backgroundColor = inChecklist
            ? UIColor(Color.skAccentSoft) : .clear
    }

    private static func iconButton(_ symbol: String, id: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol,
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)),
                   for: .normal)
        b.tintColor = UIColor(Color.skTextDim)
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        b.accessibilityIdentifier = id
        b.widthAnchor.constraint(equalToConstant: 33).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }
}

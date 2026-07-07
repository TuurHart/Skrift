import UIKit
import SwiftUI

/// The editor's keyboard accessory — a floating Skrift pill (same glass language
/// as the player bar), NOT the flat system strip (signed-off in
/// `mocks/note-editor-redesign.html`): undo · redo · find-in-note ·
/// photo-at-caret · Done. Installed as the text view's `inputAccessoryView`
/// with a clear background so only the pill shows above the keyboard.
final class NoteAccessoryBar: UIView {
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onFind: (() -> Void)?
    var onPhoto: (() -> Void)?
    var onDone: (() -> Void)?

    private let undoButton = NoteAccessoryBar.iconButton("arrow.uturn.backward", id: "accessory-undo")
    private let redoButton = NoteAccessoryBar.iconButton("arrow.uturn.forward", id: "accessory-redo")
    private let findButton = NoteAccessoryBar.iconButton("magnifyingglass", id: "accessory-find")
    private let photoButton = NoteAccessoryBar.iconButton("camera", id: "accessory-photo")
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
        findButton.addAction(UIAction { [weak self] _ in self?.onFind?() }, for: .touchUpInside)
        photoButton.addAction(UIAction { [weak self] _ in self?.onPhoto?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [undoButton, redoButton, divider, findButton, photoButton,
                                                   UIView(), doneButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.setCustomSpacing(8, after: redoButton)
        stack.setCustomSpacing(8, after: divider)
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

    /// Reflect the text view's undo stack (called on begin-editing and per edit).
    func refresh(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    private static func iconButton(_ symbol: String, id: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol,
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)),
                   for: .normal)
        b.tintColor = UIColor(Color.skTextDim)
        b.accessibilityIdentifier = id
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }
}

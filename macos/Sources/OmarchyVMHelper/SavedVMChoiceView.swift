import AppKit

/// The saved VM chooser inside the start menu's alert: one radio button per
/// disk, with what the storage layer records about it underneath.
final class SavedVMChoiceView: NSStackView {
    private let candidates: [SavedVMCandidate]
    private var buttons: [NSButton] = []
    var selectionChanged: (() -> Void)?

    var selectedCandidate: SavedVMCandidate? {
        guard let index = buttons.firstIndex(where: { $0.state == .on }) else { return nil }
        return candidates[index]
    }

    init(candidates: [SavedVMCandidate], bundledIdentity: String?, width: CGFloat = 360) {
        self.candidates = candidates
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 10

        let preferred = SavedVMChoice.preferredCandidate(in: candidates)
        for candidate in candidates {
            let button = NSButton(
                radioButtonWithTitle: SavedVMChoice.title(for: candidate),
                target: self,
                action: #selector(choose(_:))
            )
            button.isEnabled = candidate.isLaunchable
            button.state = candidate == preferred ? .on : .off
            button.identifier = NSUserInterfaceItemIdentifier("saved-vm-\(candidate.name)")
            buttons.append(button)

            let detail = NSTextField(wrappingLabelWithString: SavedVMChoice.detail(
                for: candidate,
                bundledIdentity: bundledIdentity
            ))
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detail.textColor = .secondaryLabelColor
            detail.preferredMaxLayoutWidth = width - 20

            let entry = NSStackView(views: [button, detail])
            entry.orientation = .vertical
            entry.alignment = .leading
            entry.spacing = 2
            entry.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            detail.leadingAnchor.constraint(equalTo: entry.leadingAnchor, constant: 20).isActive = true
            addArrangedSubview(entry)
        }
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: fittingSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc private func choose(_ sender: NSButton) {
        for button in buttons where button !== sender {
            button.state = .off
        }
        sender.state = .on
        selectionChanged?()
    }
}

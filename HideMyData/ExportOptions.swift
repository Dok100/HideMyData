import AppKit

struct ExportOptions {
    var removeMetadata = true
}

@MainActor
final class ExportOptionsAccessoryView: NSStackView {
    private let removeMetadataCheckbox: NSButton

    var options: ExportOptions {
        ExportOptions(removeMetadata: removeMetadataCheckbox.state == .on)
    }

    init() {
        removeMetadataCheckbox = NSButton(
            checkboxWithTitle: "Metadaten entfernen",
            target: nil,
            action: nil
        )
        removeMetadataCheckbox.state = .on

        let note = NSTextField(labelWithString: "Entfernt nach Möglichkeit EXIF-, GPS- und PDF-Dokumenteigenschaften sowie Anmerkungen, Links, Formulare und versteckte Dokumentdaten.")
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byWordWrapping
        note.preferredMaxLayoutWidth = 360

        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        addArrangedSubview(removeMetadataCheckbox)
        addArrangedSubview(note)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 360).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}

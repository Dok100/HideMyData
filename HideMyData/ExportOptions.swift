import AppKit

struct ExportOptions {
    var removeMetadata = true
}

struct ExportValidationReport: Equatable {
    enum Format: Equatable {
        case pdf
        case image
    }

    let format: Format
    let redactionCount: Int
    let redactedPageCount: Int?
    let totalPageCount: Int?
    let removedMetadata: Bool
    let annotationsRemoved: Bool
    let bakedIntoPixels: Bool

    var shortStatusText: String {
        switch format {
        case .pdf:
            if let redactedPageCount, let totalPageCount {
                return "PDF gespeichert · \(redactedPageCount) von \(totalPageCount) Seite\(totalPageCount == 1 ? "" : "n") neu aufgebaut"
            }
            return "PDF gespeichert"
        case .image:
            return "Bild gespeichert · Schwärzungen fest übernommen"
        }
    }

    var trustChecklist: [String] {
        var items: [String] = []
        if bakedIntoPixels {
            items.append("Schwärzungen sind fest im Export enthalten")
        }
        if annotationsRemoved {
            items.append("Anmerkungen und Overlays wurden nicht übernommen")
        }
        if removedMetadata {
            items.append("Metadaten wurden entfernt")
        }
        return items
    }
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

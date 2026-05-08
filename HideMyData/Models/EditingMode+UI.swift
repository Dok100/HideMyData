import Foundation

extension EditingMode {
    var helpText: String {
        switch self {
        case .view: "Ansehen — durch das Dokument scrollen"
        case .add: "Hinzufügen — ziehen, um einen Bereich zu markieren"
        case .remove: "Entfernen — auf ein Feld klicken, um die Markierung zu entfernen"
        }
    }
}

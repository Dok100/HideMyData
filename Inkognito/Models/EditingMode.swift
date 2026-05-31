import Foundation

enum EditingMode: String, CaseIterable, Identifiable {
    case view
    case add
    case remove

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .view:
            return "Ansehen"
        case .add:
            return "Hinzufügen"
        case .remove:
            return "Entfernen"
        }
    }

    var systemImage: String {
        switch self {
        case .view:
            return "eye"
        case .add:
            return "plus.square"
        case .remove:
            return "minus.square"
        }
    }
}

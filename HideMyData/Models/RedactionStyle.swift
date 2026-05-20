import Foundation

enum RedactionStyle: String, CaseIterable, Identifiable {
    case blackRectangle
    case blur

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .blackRectangle:
            return "Schwarz"
        case .blur:
            return "Unschärfe"
        }
    }
}

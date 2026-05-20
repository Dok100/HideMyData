import Foundation

extension RedactionStyle {
    var systemImage: String {
        switch self {
        case .blackRectangle:
            return "square.fill"
        case .blur:
            return "camera.filters"
        }
    }
}

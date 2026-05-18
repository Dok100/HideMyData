import Foundation
import PDFKit
import AppKit
import SwiftUI

enum FindingVisualSemantics {
    static let accountNumberColor = NSColor(
        calibratedHue: 0.12,
        saturation: 0.72,
        brightness: 0.88,
        alpha: 1
    )

    static func displayName(for category: String) -> String {
        switch category.lowercased() {
        case "private_person":
            return "Person"
        case "private_phone":
            return "Telefon"
        case "private_email":
            return "E-Mail"
        case "private_date":
            return "Datum"
        case "private_address", "adresse":
            return "Adresse"
        case "adressblock":
            return "Adressblock"
        case "kontakt":
            return "Kontakt"
        case "account_number":
            return "Kontonummer"
        case "custom_identifier":
            return "Eigene Regel"
        case "secret":
            return "Vertraulich"
        default:
            return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func nsColor(for category: String) -> NSColor {
        switch category.lowercased() {
        case "private_email":
            return .systemGreen
        case "kontakt":
            return .systemTeal
        case "private_address", "adressblock", "adresse":
            return .systemRed
        case "account_number":
            return accountNumberColor
        case "private_phone":
            return .systemBlue
        case "private_person":
            return .systemIndigo
        case "private_date":
            return .systemPurple
        case "custom_identifier":
            return .systemOrange
        case "secret":
            return .systemPink
        default:
            return .systemOrange
        }
    }

    static func color(for category: String) -> Color {
        Color(nsColor: nsColor(for: category))
    }

    static var legendItems: [(title: String, category: String)] {
        [
            ("Person", "private_person"),
            ("Adresse", "private_address"),
            ("Nummer", "account_number"),
            ("Kontakt", "kontakt"),
            ("Datum", "private_date"),
            ("E-Mail", "private_email")
        ]
    }
}

enum StatusVisualSemantics {
    static let reviewComplete = Color.green
    static let trust = Color.blue
    static let attention = Color.orange
    static let danger = Color.red
    static let neutral = Color.secondary
    static let regex = Color.mint

    static func softFill(_ tone: Color, colorScheme: ColorScheme, strong: Bool = false) -> Color {
        tone.opacity(colorScheme == .dark ? (strong ? 0.20 : 0.16) : (strong ? 0.12 : 0.08))
    }

    static func softBorder(_ tone: Color, colorScheme: ColorScheme) -> Color {
        tone.opacity(colorScheme == .dark ? 0.28 : 0.18)
    }

    static func pillTint(for kind: StatusPillContent.Kind) -> Color {
        switch kind {
        case .progress:
            return trust.opacity(0.18)
        case .info:
            return Color.clear
        case .success:
            return reviewComplete.opacity(0.16)
        case .warning:
            return attention.opacity(0.18)
        }
    }

    static func pillForeground(for kind: StatusPillContent.Kind) -> AnyShapeStyle {
        switch kind {
        case .progress, .info:
            return AnyShapeStyle(.secondary)
        case .success:
            return AnyShapeStyle(.primary)
        case .warning:
            return AnyShapeStyle(attention)
        }
    }

    static func pillIconStyle(for kind: StatusPillContent.Kind) -> AnyShapeStyle {
        switch kind {
        case .progress:
            return AnyShapeStyle(.secondary)
        case .info:
            return AnyShapeStyle(trust)
        case .success:
            return AnyShapeStyle(reviewComplete)
        case .warning:
            return AnyShapeStyle(attention)
        }
    }

    static func reviewStatusTone(for status: ReviewStatus) -> Color {
        switch status {
        case .pending:
            return attention
        case .accepted:
            return reviewComplete
        case .rejected:
            return danger
        }
    }

    static func detectionSourceTone(for source: DetectionSource) -> Color {
        switch source {
        case .model:
            return trust
        case .pattern:
            return regex
        case .mixed:
            return attention
        }
    }
}

enum SurfaceVisualSemantics {
    static func elevatedPanelFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.88)
            : Color(nsColor: .controlBackgroundColor).opacity(0.96)
    }

    static func elevatedPanelBorder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    static func secondaryPanelFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.74)
    }

    static func secondaryPanelBorder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    static func selectionAccentFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.accentColor.opacity(0.16) : Color.accentColor.opacity(0.11)
    }

    static func selectionAccentBorder(colorScheme: ColorScheme) -> Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.68 : 0.52)
    }

    static func selectionShadow(colorScheme: ColorScheme) -> Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
    }
}

nonisolated final class BlackRedactionAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
    }
}

nonisolated final class PreviewRedactionAnnotation: PDFAnnotation {
    var tintColor: NSColor = .systemOrange

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let fill = tintColor.withAlphaComponent(0.22).cgColor
        let stroke = tintColor.withAlphaComponent(0.85).cgColor

        context.saveGState()
        context.setFillColor(fill)
        context.fill(bounds)
        context.setStrokeColor(stroke)
        context.setLineWidth(2)
        context.stroke(bounds)
        context.restoreGState()
    }
}

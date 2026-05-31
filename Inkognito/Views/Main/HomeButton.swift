import SwiftUI

struct HomeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Übersicht", systemImage: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Zur Übersicht zurück  ⌘H")
        .keyboardShortcut("h", modifiers: [.command])
    }
}

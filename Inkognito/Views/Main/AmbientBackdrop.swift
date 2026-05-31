import SwiftUI
import AppKit

struct AmbientBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.075, green: 0.078, blue: 0.086)

                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.115, blue: 0.125),
                        Color(red: 0.07, green: 0.074, blue: 0.082)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.0)
                    ],
                    center: .top,
                    startRadius: 30,
                    endRadius: 420
                )

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color.clear,
                        Color.blue.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(nsColor: .windowBackgroundColor)

                LinearGradient(
                    colors: [
                        Color(red: 0.985, green: 0.988, blue: 0.993),
                        Color(red: 0.956, green: 0.965, blue: 0.975)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.78),
                        Color.white.opacity(0.0)
                    ],
                    center: .top,
                    startRadius: 40,
                    endRadius: 520
                )

                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.94, blue: 0.98).opacity(0.16),
                        Color.clear,
                        Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct WindowGlassConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowConfiguringView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

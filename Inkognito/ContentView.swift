import SwiftUI

struct ContentView: View {
    @State private var detector = PIIDetector()
    @State private var pdfRedactor = PDFRedactor()
    @State private var imageRedactor = ImageRedactor()
    @State private var recents = RecentsStore()
    @State private var customPatterns = CustomPatternStore()
    @State private var inputMode: InputMode = .pdf

    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    var body: some View {
        rootScreen
            .frame(minWidth: 980, minHeight: 760)
            .background(AmbientBackdrop())
            .background(WindowGlassConfigurator())
            .task {
                await detector.loadIfCached()
            }
    }

    @ViewBuilder
    private var rootScreen: some View {
        if shouldShowIntro {
            IntroView {
                hasSeenIntro = true
            }
        } else if needsModelPreparation {
            FirstRunView(detector: detector)
        } else {
            MainView(
                detector: detector,
                pdfRedactor: pdfRedactor,
                imageRedactor: imageRedactor,
                recents: recents,
                customPatterns: customPatterns,
                inputMode: $inputMode
            )
        }
    }

    private var shouldShowIntro: Bool {
        !hasSeenIntro
    }

    private var needsModelPreparation: Bool {
        switch detector.phase {
        case .needsDownload, .downloading, .failed:
            true
        default:
            false
        }
    }
}

#Preview {
    ContentView()
}

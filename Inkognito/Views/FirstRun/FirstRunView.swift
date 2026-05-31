import SwiftUI

struct FirstRunView: View {
    @Bindable var detector: PIIDetector

    @State private var headerVisible = false
    @State private var sourceVisible = false
    @State private var phaseVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            header
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 10)

            Spacer(minLength: 34)

            ModelSourceCard()
                .frame(maxWidth: 480)
                .padding(.horizontal, 40)
                .opacity(sourceVisible ? 1 : 0)
                .offset(y: sourceVisible ? 0 : 8)

            Spacer(minLength: 26)

            FirstRunPhase(detector: detector)
                .frame(minHeight: 70)
                .opacity(phaseVisible ? 1 : 0)
                .offset(y: phaseVisible ? 0 : 8)

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: runEntranceAnimation)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("Modell lokal vorbereiten")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)

            Text("""
            Inkognito lädt einmal ein kleines Sprachmodell und nutzt es danach vollständig lokal auf deinem Mac. \
            Dokumente bleiben auf dem Gerät. Für Bilder nutzt Inkognito zusätzlich Apple Vision, das bereits lokal vorhanden ist.
            """)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 40)
    }

    private func runEntranceAnimation() {
        withAnimation(.smooth(duration: 0.55)) {
            headerVisible = true
        }
        withAnimation(.smooth(duration: 0.55).delay(0.12)) {
            sourceVisible = true
        }
        withAnimation(.smooth(duration: 0.55).delay(0.24)) {
            phaseVisible = true
        }
    }
}

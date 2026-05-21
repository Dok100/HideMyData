import SwiftUI

struct IntroView: View {
    let onContinue: () -> Void

    @State private var headerVisible = false
    @State private var benefitsVisible = false
    @State private var actionVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            introHeader
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 12)

            Spacer(minLength: 40)

            benefitList
                .opacity(benefitsVisible ? 1 : 0)
                .offset(y: benefitsVisible ? 0 : 12)

            Spacer(minLength: 40)

            primaryAction
                .opacity(actionVisible ? 1 : 0)
                .offset(y: actionVisible ? 0 : 10)

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .onAppear(perform: runEntranceAnimation)
    }

    private var introHeader: some View {
        VStack(spacing: 18) {
            IntroAppLogo()

            VStack(spacing: 10) {
                Text("Willkommen bei Inkognito")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)

                Text("Dateien und Texte anonymisieren. Direkt auf deinem Mac.\nVertrauliche Inhalte aus PDFs, Bildern und der Zwischenablage bleiben auf deinem Gerät.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 24) {
            IntroBenefit(
                icon: "lock.shield.fill",
                tint: .green,
                title: "Lokal und privat",
                text: "Erkennung, Review und Export laufen vollständig auf deinem Mac. Keine Konten, keine Server, keine Cloud."
            )
            IntroBenefit(
                icon: "sparkles",
                tint: .indigo,
                title: "Dateien und Inhalte anonymisieren",
                text: "Inkognito erkennt sensible Stellen in PDFs, Bildern und kopierten Texten, damit du sie vor dem Weitergeben gezielt anonymisieren kannst."
            )
            IntroBenefit(
                icon: "rectangle.on.rectangle.angled",
                tint: .orange,
                title: "Vor dem Export prüfen",
                text: "Vor dem Speichern prüfst du die Treffer. Beim Export werden bestätigte Schwärzungen oder Anonymisierungen zuverlässig fest übernommen."
            )
        }
        .frame(maxWidth: 580, alignment: .leading)
    }

    private var primaryAction: some View {
        Button(action: onContinue) {
            Text("Weiter")
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 220)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private func runEntranceAnimation() {
        withAnimation(.smooth(duration: 0.55)) {
            headerVisible = true
        }
        withAnimation(.smooth(duration: 0.55).delay(0.14)) {
            benefitsVisible = true
        }
        withAnimation(.smooth(duration: 0.55).delay(0.28)) {
            actionVisible = true
        }
    }
}

private struct IntroAppLogo: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 104

    var body: some View {
        Image(.appLogo)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.22))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .accessibilityLabel("Inkognito")
    }
}

private struct IntroBenefit: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    IntroView(onContinue: {})
        .frame(width: 760, height: 600)
        .background(AmbientBackdrop())
}

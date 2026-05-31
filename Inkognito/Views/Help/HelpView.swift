import SwiftUI

private enum HelpTopic: String, CaseIterable, Identifiable {
    case quickStart = "Schnellstart"
    case anonymizeFiles = "Dateien und Text schützen"
    case reviewAndExport = "Treffer prüfen"
    case customRules = "Eigene Regeln"
    case commonQuestions = "Typische Fragen"
    case privacy = "Datenschutz"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .quickStart: "bolt.fill"
        case .anonymizeFiles: "doc.text.magnifyingglass"
        case .reviewAndExport: "checklist"
        case .customRules: "slider.horizontal.3"
        case .commonQuestions: "questionmark.circle"
        case .privacy: "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .quickStart: .orange
        case .anonymizeFiles: .blue
        case .reviewAndExport: .green
        case .customRules: .indigo
        case .commonQuestions: .brown
        case .privacy: .teal
        }
    }

    var subtitle: String {
        switch self {
        case .quickStart:
            "Was Inkognito macht und wie du schnell loslegst."
        case .anonymizeFiles:
            "Wie Dokumente geschwärzt und kopierte Texte für KI-Tools vorbereitet werden."
        case .reviewAndExport:
            "Wie du Treffer bestätigst und geschützt exportierst."
        case .customRules:
            "Wann eigene Regeln sinnvoll helfen und wo ihre Grenzen liegen."
        case .commonQuestions:
            "Kurze Antworten auf typische Unsicherheiten."
        case .privacy:
            "Warum Inhalte auf deinem Mac bleiben."
        }
    }
}

struct HelpView: View {
    @State private var selectedTopic: HelpTopic? = .quickStart

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                        Text(topic.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: topic.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(topic.tint)
                        .frame(width: 22, height: 22)
                }
                .tag(topic)
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .navigationTitle("Hilfe")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            if let topic = selectedTopic {
                detailView(for: topic)
            } else {
                ContentUnavailableView("Thema auswählen", systemImage: "questionmark.circle")
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    @ViewBuilder
    private func detailView(for topic: HelpTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(for: topic)

                switch topic {
                case .quickStart:
                    QuickStartContent()
                case .anonymizeFiles:
                    AnonymizeFilesContent()
                case .reviewAndExport:
                    ReviewAndExportContent()
                case .customRules:
                    CustomRulesContent()
                case .commonQuestions:
                    CommonQuestionsContent()
                case .privacy:
                    PrivacyContent()
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(for topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(topic.rawValue, systemImage: topic.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            Text(topic.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct QuickStartContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpLead(
                "Inkognito hat zwei gleichwertige Wege: sensible Stellen in PDFs und Bildern schützen oder kopierten Text für KI-Tools anonymisieren und später wieder zurückführen. Beides läuft lokal auf deinem Mac."
            )

            HelpCallout(
                icon: "sparkles",
                tint: .orange,
                text: "Für Dokumente prüfst du Treffer vor dem Export. Für kopierten Text arbeitest du mit Platzhaltern, damit Antworten aus einem KI-Tool später wieder personalisiert werden können."
            )

            HelpSection("Wann nutze ich welchen Weg?") {
                HelpBulletList(items: [
                    "Dokumente schützen: wenn du PDFs oder Bilder vor dem Teilen geschwärzt exportieren willst.",
                    "Text für KI-Tools vorbereiten: wenn vertrauliche Inhalte erst anonymisiert an ein Large Language Modell gehen und danach wieder zurückgeführt werden sollen."
                ])
            }

            HelpSection("Dokumente schützen") {
                HelpStep(number: "1", title: "PDF oder Bild öffnen", detail: "Öffne ein Dokument im Hauptfenster und starte die Erkennung.")
                HelpStep(number: "2", title: "Treffer prüfen", detail: "Bestätige passende Treffer, lehne unnötige ab und ergänze fehlende Stellen bei Bedarf manuell.")
                HelpStep(number: "3", title: "Geschützt exportieren", detail: "Speichere danach eine anonymisierte Fassung zum Weitergeben.")
            }

            HelpSection("Text für KI-Tools vorbereiten") {
                HelpStep(number: "1", title: "Text aus der Zwischenablage laden", detail: "Inkognito anonymisiert kopierten Text lokal und ersetzt sensible Stellen durch Platzhalter.")
                HelpStep(number: "2", title: "Anonymisierte Fassung im KI-Tool verwenden", detail: "Gib nur die geschützte Version an ein Large Language Modell weiter.")
                HelpStep(number: "3", title: "Antwort zurückführen", detail: "Lade die KI-Antwort wieder in Inkognito, damit Platzhalter mit den Originalwerten zurückverwandelt werden.")
            }
        }
    }
}

private struct AnonymizeFilesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpLead(
                "Inkognito schützt vertrauliche Inhalte in zwei Formen: als geschwärzte Dokumente zum Teilen und als anonymisierte Textfassung für die Arbeit mit KI-Tools."
            )

            HelpSection("Typische Treffer") {
                HelpBulletList(items: [
                    "Namen und Anreden",
                    "Adressen",
                    "E-Mail-Adressen und Telefonnummern",
                    "Konto-, Referenz- oder Kennnummern",
                    "wiederkehrende Begriffe über eigene Regeln"
                ])
            }

            HelpSection("Zwei typische Anwendungsfälle") {
                HelpBulletList(items: [
                    "PDFs oder Bilder prüfen und als geschützte Fassung exportieren.",
                    "Kopierten Text anonymisieren, in ein Large Language Modell einfügen und die Antwort später wieder zurückführen."
                ])
            }

            HelpSection("Wichtig für die Praxis") {
                HelpBulletList(items: [
                    "PDFs mit nativem Text sind meist stabiler als reine Scans.",
                    "Bei eingescannten Dokumenten lohnt sich eine sorgfältigere Sichtprüfung.",
                    "Bereits beschädigte, unscharfe oder teilweise geschwärzte Ausgangsdokumente können die Erkennung erschweren."
                ])
            }

            HelpCallout(
                icon: "eye",
                tint: .blue,
                text: "Inkognito soll Review erleichtern, nicht ersetzen. Eine kurze Sichtprüfung bleibt Teil des Workflows."
            )
        }
    }
}

private struct ReviewAndExportContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpLead(
                "Nach der Erkennung prüfst du Treffer im Review. So entscheidest du bewusst, was in der exportierten Fassung geschützt bleibt."
            )

            HelpSection("So läuft das Review ab") {
                HelpBulletList(items: [
                    "Bestätige Treffer, die anonymisiert werden sollen.",
                    "Lehne Stellen ab, die nicht geschützt werden müssen.",
                    "Nutze manuelle Schwärzungen, wenn etwas fehlt oder bewusst anders abgedeckt werden soll."
                ])
            }

            HelpSection("Vor dem Export") {
                HelpBulletList(items: [
                    "Prüfe besonders Namen, Anreden und freie Textstellen auf vollständige Abdeckung.",
                    "Achte bei mehrseitigen PDFs auch auf spätere Seiten.",
                    "Exportiere erst, wenn keine offenen Review-Entscheidungen mehr übrig sind."
                ])
            }

            HelpCallout(
                icon: "square.and.arrow.down",
                tint: .green,
                text: "Beim geschützten Export werden bestätigte Schwärzungen fest in die neue Fassung übernommen."
            )

            HelpSection("Beim KI-Workflow statt Export") {
                HelpBulletList(items: [
                    "Für kopierten Text erzeugt Inkognito eine anonymisierte Fassung mit Platzhaltern.",
                    "Die Antwort aus dem KI-Tool kann danach wieder geladen und mit den Originalwerten zurückgeführt werden.",
                    "Prüfe auch hier die zurückgeführte Antwort kurz, bevor du sie weiterverwendest."
                ])
            }
        }
    }
}

private struct CustomRulesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpLead(
                "Eigene Regeln sind besonders hilfreich, wenn dieselben Personen, Adressen oder Kennungen regelmäßig in Dokumenten auftauchen."
            )

            HelpSection("Was eigene Regeln leisten") {
                HelpBulletList(items: [
                    "Sie helfen bei wiederkehrenden Namen, Adressen, Kennungen oder organisationsspezifischen Begriffen.",
                    "Inkognito kann daraus zusätzliche Teiltreffer ableiten, damit naheliegende Varianten leichter wiedergefunden werden.",
                    "Sie machen wiederkehrende Review-Aufgaben schneller und konsistenter."
                ])
            }

            HelpSection("Wo ihre Grenzen liegen") {
                HelpBulletList(items: [
                    "Eigene Regeln ersetzen die Sichtprüfung nicht.",
                    "Bei schwacher OCR, Scans oder stark abweichenden Schreibweisen können Treffer unvollständig sein.",
                    "Teiltreffer sind als Unterstützung gedacht, nicht als Garantie für jede mögliche Formulierung."
                ])
            }

            HelpCallout(
                icon: "checkmark.shield",
                tint: .indigo,
                text: "Prüfe Treffer vor dem Export trotzdem kurz, besonders bei Scans oder uneinheitlichen Schreibweisen."
            )
        }
    }
}

private struct CommonQuestionsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpSection("Warum fehlt manchmal ein Name?") {
                HelpAnswer("Scans, OCR-Fehler oder ungewöhnliche Schreibweisen können dazu führen, dass einzelne Stellen nicht automatisch gefunden werden. Ergänze solche Stellen im Review manuell.")
            }

            HelpSection("Warum ist eine Adresse nur teilweise erkannt?") {
                HelpAnswer("Manche Dokumente trennen Adressbestandteile über Zeilen, Spalten oder OCR-Brüche. Dadurch kann Inkognito nur Teile sicher erkennen. Prüfe solche Bereiche vor dem Export besonders sorgfältig.")
            }

            HelpSection("Warum helfen eigene Regeln bei OCR-Fehlern nicht immer sofort?") {
                HelpAnswer("Wenn der zugrunde liegende Text bereits falsch erkannt wurde, kann auch eine passende Regel daran vorbeigehen. Eigene Regeln helfen am besten bei stabilen, wiederkehrenden Schreibweisen.")
            }

            HelpSection("Warum sollte ich den Export vor dem Teilen prüfen?") {
                HelpAnswer("Die exportierte Fassung ist zum Weitergeben gedacht. Eine letzte Sichtprüfung stellt sicher, dass sensible Inhalte vollständig abgedeckt sind und keine unnötigen Schwärzungen geblieben sind.")
            }
        }
    }
}

private struct PrivacyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpLead(
                "Inkognito ist darauf ausgelegt, vertrauliche Inhalte lokal zu verarbeiten. Das hilft beim Schutz sensibler Dokumente im Alltag."
            )

            HelpSection("Datenschutz auf einen Blick") {
                HelpBulletList(items: [
                    "Dokumente und Inhalte bleiben auf deinem Gerät.",
                    "Für die Nutzung ist kein Konto erforderlich.",
                    "Inhaltsdaten werden nicht an eine Cloud zur Verarbeitung weitergegeben."
                ])
            }

            HelpCallout(
                icon: "desktopcomputer",
                tint: .teal,
                text: "Auch Modellvorbereitung und Erkennung sind auf lokale Verarbeitung ausgerichtet, damit sensible Inhalte auf deinem Mac bleiben."
            )
        }
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            content
        }
    }
}

private struct HelpLead: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpCallout: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HelpStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HelpBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(item)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct HelpAnswer: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    HelpView()
}

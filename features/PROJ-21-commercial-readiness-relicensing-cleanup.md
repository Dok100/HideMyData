# PROJ-21 – Commercial Readiness und Re-Licensing Cleanup

**Status**: In Arbeit

## Ziel

Das Projekt soll technisch, sichtbar und rechtlich so vorbereitet werden, dass eine spätere Monetarisierung oder ein Mac-App-Store-Release nicht an alten Lizenz- oder Herkunftsresten scheitert.

## Schwerpunkte

- sichtbare und veröffentlichte Legacy-Reste von `HideMyData` systematisch entfernen
- Dateien mit hohem Fremdanteil priorisiert ersetzen oder neu schreiben
- Lizenz- und Rechtekette vor einer Umstellung auf ein kommerzielles Modell sauber absichern
- technische Migrationen nur dort behalten, wo sie für Bestandsnutzer noch nötig sind

## Wichtige Vorsichtspunkte

- `GPL-3.0` nicht entfernen, solange noch schutzfähige Beiträge Dritter im verteilten Werk enthalten sein könnten
- nicht nur auf Dateinamen schauen: auch kleine, aber nicht triviale Restbeiträge können rechtlich relevant sein
- Bestandsmigrationen für Cache, Recents, Clipboard und Updatepfade nicht versehentlich zerstören
- Sparkle- und Release-Historie getrennt von reinem UI- oder Source-Cleanup behandeln

## Deliverables

- Audit-Liste `rechtlich blockierend / vor Release bereinigen / kann vorerst intern bleiben`
- priorisierte Ersetzungsreihenfolge für Dateien mit hohem Maciej-Anteil
- separates Umstellungskonzept für Lizenz, README, Store-Metadaten und Release-Artefakte
- dokumentierte Entscheidung, welche Legacy-Migrationen bewusst erhalten bleiben

## Relevante Dateien

- `LICENSE`
- `README.md`
- `CHANGELOG.md`
- `Info.plist`
- `.swiftlint.yml`
- `.github/FUNDING.yml`
- `.github/workflows/build.yml`
- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- `HideMyData/ContentView.swift`
- `HideMyData/ModelDownloader.swift`
- `HideMyData/RecentsStore.swift`
- `HideMyData/PDFKitView.swift`
- `HideMyData/Views/Intro/IntroView.swift`
- `HideMyData/Views/FirstRun/`
- `HideMyData/Views/Main/ImageDocumentSurface.swift`
- `HideMyData/patterns.json`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`

## Bewertung

### Rechtlich blockierend

- `LICENSE` aktuell `GPL-3.0`, solange keine vollständige Rechteklärung oder Ersetzung erfolgt ist
- Dateien mit sehr hohem oder vollständigem Maciej-Anteil
- veröffentlichte Release-Artefakte und Metadaten, die alte Herkunft und Historie sichtbar konservieren

### Vor Release bereinigen

- sichtbare Produkt-, Store- und Release-Reste von `HideMyData`
- Sparkle-Historie und alte HTML-/Appcast-Dateien
- Funding-, Workflow- und Repo-Metadaten mit alter Herkunft

### Kann vorerst intern bleiben

- interne Ordnernamen wie `HideMyData/`, solange sie nicht nutzersichtbar oder rechtlich problematisch sind
- technische Legacy-Migrationspfade für Bestandsnutzer
- Dateien, in denen heutiger Code klar überwiegend von `Dok100` stammt, aber noch geringe Altanteile enthalten

## Priorisierung

### Phase 1 – Sichtbare und einfache Bereinigung

- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- `.github/FUNDING.yml`
- `.swiftlint.yml`
- `Info.plist`

Ziel:
Außenwirkung und veröffentlichte Herkunft bereinigen, ohne gleich die Kernlogik anzufassen.

### Phase 2 – UI- und Onboarding-Bausteine neu schreiben

- `HideMyData/ContentView.swift`
- `HideMyData/Views/Intro/IntroView.swift`
- `HideMyData/Views/FirstRun/FirstRunPhase.swift`
- `HideMyData/Views/FirstRun/FirstRunView.swift`
- `HideMyData/Views/FirstRun/ModelSourceCard.swift`
- `HideMyData/Views/Status/StatusPill.swift`
- `HideMyData/Views/Main/RecentsRow.swift`

Ziel:
Dateien mit sehr hohem Altanteil zuerst ersetzen, wo das Risiko technisch vergleichsweise kontrollierbar bleibt.

### Phase 3 – Infrastruktur und Utility ersetzen

- `HideMyData/ModelDownloader.swift`
- `HideMyData/RecentsStore.swift`
- `HideMyData/PDFKitView.swift`
- `HideMyData/Views/Main/ImageDocumentSurface.swift`
- `HideMyData/BlurRedactionAnnotation.swift`
- `HideMyData/Models/RedactionStyle+UI.swift`

Ziel:
Technische Altbausteine kontrolliert neu aufsetzen, ohne das Produktversprechen zu verlieren.

### Phase 4 – Fachlogik mit Restanteilen gezielt neu strukturieren

- `HideMyData/patterns.json`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`

Ziel:
Die fachlich sensiblen Kernpfade so umarbeiten, dass am Ende keine größeren Altblöcke mehr auf Drittautor-Beiträgen beruhen.

## Bekannte Ausgangslage

- sehr geringer Altanteil:
  - `HideMyData/PIIDetector.swift`
  - `HideMyData/PatternMatcher.swift`
  - `HideMyData/Views/Main/MainView.swift`
- merklicher, aber heute nicht dominanter Altanteil:
  - `HideMyData/PDFRedactor.swift`
  - `HideMyData/ImageRedactor.swift`
  - `HideMyData/patterns.json`
- sehr hoher Altanteil:
  - `HideMyData/ContentView.swift`
  - `HideMyData/Views/Intro/IntroView.swift`
  - `HideMyData/Views/FirstRun/*`
  - `HideMyData/ModelDownloader.swift`
  - `HideMyData/RecentsStore.swift`
  - `HideMyData/PDFKitView.swift`
  - `HideMyData/Views/Main/ImageDocumentSurface.swift`

## Umsetzung

- Dieses Projekt trennt Produkt-Cleanup und Rechte-Cleanup bewusst von normalen Feature-Projekten.
- Vor jeder Lizenzumstellung wird zuerst die Dateibasis nach Fremdanteilen priorisiert ersetzt oder neu aufgebaut.
- Nutzerrelevante Migrationen bleiben nur dort bestehen, wo sie keine neue rechtliche Herkunft transportieren, sondern ausschließlich Bestandsdaten sichern.
- Phase 1 wurde defensiv gestartet: sichtbare Funding- und historische Personen-/Container-Referenzen wurden aus den aktiven Release-Texten entfernt, ohne historische Artefaktnamen oder Enclosure-URLs umzubenennen.
- Der erste Phase-2-Block wurde bereits ersetzt: `ContentView`, Intro-/First-Run-Fluss, `StatusPill` und `RecentsRow` wurden neu aufgebaut, ohne die eigentliche Erkennungs- oder Exportlogik anzutasten.

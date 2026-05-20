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
- `docs/commercial-readiness-audit.md`

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

Aktueller Fortschritt in Phase 4:
- PDF-spezifische Header-/Absenderblock-Unterdrückung ist in `HideMyData/PDFHeaderSuppressionSupport.swift` ausgelagert
- PDF-spezifische OCR-Zusatzanalyse fuer Fensterempfaenger-Kontext liegt jetzt in `HideMyData/PDFOCRSupplementalAnalyzer.swift`
- bildspezifische OCR-Zusatzanalyse und Fensterempfänger-Wiederherstellung ist in `HideMyData/ImageOCRSupplementalAnalyzer.swift` gebündelt
- Manifest- und Compile-Layer fuer `patterns.json` liegen jetzt getrennt in `HideMyData/PatternMatcherBuiltinSupport.swift`, waehrend die fachlichen Regexe unveraendert bleiben
- Preview-Diagnostik und Kontext-Rect-Erweiterung aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFReviewContextSupport.swift`
- Textquellenwahl, OCR-Bevorzugung und Abschluss-Hinweise aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFDetectionLifecycleSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und PDF-Export-Report aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFExportLifecycleSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und Bild-Export-Report aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageExportLifecycleSupport.swift`
- OCR-Vorbereitung, Candidate-Aufbau, Schwachtext-Hinweise und Debug-Zusammenstellung aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageDetectionLifecycleSupport.swift`
- Supplemental-Recovery und Sichtbarkeitspruefung aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageReviewRecoverySupport.swift`
- Literal-Suche, Normalisierung und Custom-Pattern-Deduplizierung aus `PatternMatcher.swift` liegen jetzt in `HideMyData/PatternMatcherLiteralSupport.swift`
- Bild-Preview-Diagnostik ist in `HideMyData/ImagePreviewDiagnosticsSupport.swift` ausgelagert
- Modellcache- und Platzhalterlogik aus `PIIDetector.swift` ist in `HideMyData/PIIDetectorModelCacheSupport.swift` und `HideMyData/PIIDetectorPlaceholderSupport.swift` verschoben
- sichtbare Pattern-/Custom-Rule-Diagnostik aus `PIIDetector.swift` ist in `HideMyData/PIIDetectorPatternDiagnosticsSupport.swift` ausgelagert
- der größere Span-Sanitizing-/Suppression-Block aus `PIIDetector.swift` liegt jetzt in `HideMyData/PIIDetectorSpanSanitizationSupport.swift`
- Dokumentklassen-Erkennung und Clipboard-Supplemental-Spans aus `PIIDetector.swift` liegen jetzt in `HideMyData/PIIDetectorSupplementalClipboardSupport.swift`
- Review-Kompaktierung und Projection-Logik fuer Trefferbloecke liegen jetzt in `HideMyData/ReviewFindingCompactor.swift`

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
- Der anschließende Infrastrukturblock wurde ersetzt: `ModelDownloader`, `RecentsStore`, `PDFKitView` und `ImageDocumentSurface` wurden bei stabilen Schnittstellen neu aufgebaut.
- Kleine Restbausteine wie `BlurRedactionAnnotation`, `RedactionStyle+UI` und `InputMode` wurden ebenfalls neu geschrieben, bevor der schwerere Kernblock beginnt.
- Der Kernblock wurde auf Shared-Modelle umgestellt: `RedactionStyle`, `EditingMode`, gemeinsame Workflow-Typen und der sichere Array-Zugriff liegen jetzt in eigenen Dateien statt eingebettet in `PDFRedactor` oder `ImageRedactor`.
- `PDFRedactor` und `ImageRedactor` verwenden diese ausgelagerten Typen inzwischen produktiv, ohne ihr Nutzerverhalten zu verändern. `patterns.json` wurde als kompletter Datenblock neu aufgebaut, während die fachlichen Regexe erhalten bleiben.
- Das Deliverable fuer den laufenden Audit-Stand liegt jetzt zusaetzlich in `docs/commercial-readiness-audit.md`, damit rechtliche Blocker, sichtbare Altspuren und bewusst verbleibende interne Reste getrennt verfolgt werden koennen.
- Der naechste Entkopplungsschritt ist ebenfalls erfolgt: Rasterisierung, Blur-Rendering und Bake-Logik fuer Bild- und PDF-Export liegen nun zentral in `RedactionRendering.swift` statt doppelt in beiden Redactoren.
- Reine Text-Heuristiken fuer Anrede, Formularlabels, schwaches OCR sowie Fenster-/Adresszeilen liegen jetzt zusaetzlich gebuendelt in `DocumentTextHeuristics.swift` und nicht mehr verteilt in beiden Redactoren.
- OCR-Kontextanalyse fuer Formular-, Liefer- und Fensterempfaengerbloecke liegt jetzt zusaetzlich in `OCRContextAnalyzer.swift`, waehrend `OCRRecipientHeuristics.swift` die eigentliche Blockaufloesung und Headernaehe separat kapselt.
- Der verbleibende native PDF-Kontextblock fuer Empfaenger-, Kontakt- und Adressmuster wurde ebenfalls entkoppelt und liegt jetzt in `NativePDFContextAnalyzer.swift` statt direkt in `PDFRedactor`.
- Die kleineren PDF-Textkontext-Helfer fuer Recipient-Marker und Label-Kontextlinien liegen nun zusaetzlich in `PDFTextContextSupport.swift`, sodass `PDFRedactor` an diesen Stellen nur noch Rects aus PDFKit ableitet.
- Auch die reine PDF-Textsuche und Rect-Aufloesung fuer Treffer-Fallbacks liegt jetzt separat in `PDFTextRectResolver.swift` statt weiterhin direkt in `PDFRedactor`.
- Die PDF-spezifische Header-/Senderblock-Suppression fuer Fehlmarkierungen liegt nun ebenfalls in `PDFHeaderSuppressionSupport.swift`, sodass `PDFRedactor` diese Regeln nicht mehr selbst traegt.

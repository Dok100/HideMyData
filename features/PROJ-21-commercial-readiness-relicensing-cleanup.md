# PROJ-21 – Commercial Readiness und Re-Licensing Cleanup

**Status**: Abgeschlossen

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
- separater Folgeblock fuer die Spaeter-Neuaufsetzung der Sparkle-Historie und Distribution statt einer stillen Umschreibung der Alt-Artefakte

## Definition of Done

`PROJ-21` gilt erst dann als abgeschlossen, wenn alle folgenden Punkte erfuellt sind:

1. Die fachlichen Kernpfade aus Phase 4 sind in ihrem aktuellen Zuschnitt bewusst akzeptiert oder weiter reduziert, und groessere Altbloecke gelten nicht mehr als offener Prioritaetsblock.
2. Die rechtlich blockierenden Punkte aus `docs/commercial-readiness-audit.md` sind fuer den angestrebten Produktstand entschieden: entweder ersetzt, geklaert oder bewusst als Restblock dokumentiert.
3. Die Lizenz- und Rechtekettenentscheidung fuer das distribuierte Werk ist dokumentiert; insbesondere wird `LICENSE` nicht mehr nur als offener Platzhalterzustand gefuehrt.
4. README-, Release- und Store-nahe Metadaten sind auf den realen Produkt- und Distributionsstand abgeglichen, soweit sie nicht bewusst an `PROJ-22` ausgelagert wurden.
5. Bewusst beibehaltene Legacy-Migrationspfade sind dokumentiert, und ihre Beibehaltung ist fachlich begruendet statt nur historisch gewachsen.
6. Der getrennte Sparkle-/Distributionsreset ist klar an `PROJ-22` uebergeben und wird nicht mehr als still offener Rest in `PROJ-21` mitgefuehrt.
7. Audit-, Handoff- und Entscheidungsdokumente spiegeln den Abschlussstand konsistent wider.
8. Der aktuelle Abschlussstand ist technisch verifiziert oder auf einen bereits verifizierten Stand rueckgebunden; mindestens Build und Detection-Regressionen sind fuer die letzten relevanten Codeaenderungen dokumentiert.

## Abschlussentscheidung

- Das bisherige Fork-Repo bleibt bewusst als Nachschlagewerk und historische Referenz bestehen.
- Das neue Repository `Dok100/Inkognito` ist die kuenftige Produktbasis.
- Im neuen Repository bleibt die Lizenz vorerst bewusst offen (`No license`), solange die geplante Kommerzialisierung vorbereitet wird.
- Die im Audit verbleibenden Kernpfade `HideMyData/patterns.json`, `HideMyData/PDFRedactor.swift`, `HideMyData/ImageRedactor.swift`, `HideMyData/PIIDetector.swift` und `HideMyData/PatternMatcher.swift` werden im aktuellen Stand bewusst akzeptiert; es ist keine weitere Reduzierung innerhalb von `PROJ-21` geplant.
- Der Sparkle-/Distributionsreset bleibt separat an `PROJ-22` uebergeben.

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

Status Phase 4:
- inhaltlich abgeschlossen
- weitere Eingriffe in `HideMyData/PDFRedactor.swift`, `HideMyData/ImageRedactor.swift` oder `HideMyData/patterns.json` nur noch bei klar begruendetem fachlichem Mehrwert

Abschlussstand von Phase 4:
- PDF-spezifische Header-/Absenderblock-Unterdrückung ist in `HideMyData/PDFHeaderSuppressionSupport.swift` ausgelagert
- PDF-spezifische OCR-Zusatzanalyse fuer Fensterempfaenger-Kontext liegt jetzt in `HideMyData/PDFOCRSupplementalAnalyzer.swift`
- bildspezifische OCR-Zusatzanalyse und Fensterempfänger-Wiederherstellung ist in `HideMyData/ImageOCRSupplementalAnalyzer.swift` gebündelt
- Manifest- und Compile-Layer fuer `patterns.json` liegen jetzt getrennt in `HideMyData/PatternMatcherBuiltinSupport.swift`, waehrend die fachlichen Regexe unveraendert bleiben
- `Regex-Pattern-Bibliothek.Json` liegt jetzt zusaetzlich als validierte Quellbibliothek vor; die App laedt zur Laufzeit weiterhin nur das kuratierte Manifest `HideMyData/patterns.json`, aus dem die polnischen Regex-Blöcke entfernt wurden, waehrend die Bibliothek die aktuelle Runtime-Teilmenge vollstaendig mittraegt
- `HideMyData/patterns.json` beschreibt seine Runtime-Rolle jetzt selbst ueber Manifest-Metadaten wie `role`, `pattern_count`, `runtime_scope` und die direkte Referenz auf `Regex-Pattern-Bibliothek.Json`, ohne die Erkennungslogik zu veraendern
- `HideMyData/patterns.json` traegt jetzt ausserdem ein explizites `selection_profile` und dokumentierte `selection_principles`, damit der Runtime-Manifestcharakter auch datenstrukturell klarer vom breiteren Quellenkatalog getrennt bleibt
- `HideMyData/patterns.json` ist jetzt zudem fachlich enger kuratiert: Entwickler-Token- und Krypto-Adressmuster bleiben in der Quellenbibliothek, laufen aber nicht mehr in der App-Runtime mit
- `HideMyData/patterns.json` fuehrt ausserdem keine nicht dokumentzentrierten Secret-/Netzwerkmuster wie IPv4, IPv6, MAC, JWT, US-SSN oder UK-NINO mehr in der Runtime, waehrend diese in der Quellenbibliothek dokumentiert bleiben
- `HideMyData/patterns.json` enthaelt in der Runtime ausserdem keine breiten unlabeled-Kreditkartenmuster mehr; der dokumentzentrierte Kartenfall bleibt ueber `credit_card_labeled` erhalten
- `HideMyData/patterns.json` fuehrt zudem keine breite internationale Telefonnummer ohne Dokument-Label mehr in der Runtime; erhalten bleiben die explizit gelabelten Telefon- und Mobilfelder sowie der dokumentzentrierte MRZ-Fall
- `HideMyData/patterns.json` dokumentiert bewusst behaltene Runtime-Grenzfaelle jetzt zusaetzlich ueber `retained_runtime_notes`, aktuell fuer unlabeled `email`, `mrz` und `date_eu_dotted`
- Preview-Diagnostik und Kontext-Rect-Erweiterung aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFReviewContextSupport.swift`
- Textquellenwahl, OCR-Bevorzugung und Abschluss-Hinweise aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFDetectionLifecycleSupport.swift`
- seitenweiser Review-Candidate-Aufbau, OCR-Fallback-Zuordnung und Preview-Diagnostik aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFDetectionReviewSupport.swift`
- Hit-Testing, Pending-Auswahl sowie Fokus-/Navigationshelfer aus `PDFRedactor.swift` laufen jetzt staerker ueber `HideMyData/PDFAnnotationReviewLifecycleSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und PDF-Export-Report aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFExportLifecycleSupport.swift`
- Review-/Annotation-Lifecycle fuer Preview-, Dismiss- und Wiederherstellungslogik aus `PDFRedactor.swift` liegt jetzt in `HideMyData/PDFAnnotationReviewLifecycleSupport.swift`
- die verbliebenen toten PDF-Review-Wrapper sowie der ungenutzte `pageCount`-Parameter wurden aus dem PDF-Review-Pfad entfernt
- Preview-zu-Redaction- und Accepted-zu-Pending-Uebergaenge fuer PDF-Review laufen jetzt ebenfalls staerker ueber `HideMyData/PDFAnnotationReviewLifecycleSupport.swift`
- Bounding-Rect-Aufloesung, UTF-16-Range-Mapping und OCR-Fallback-Rects aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFBoundingRectSupport.swift`
- Annotation-Styling, Preview-Farbgebung und Bounds-Normalisierung aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFAnnotationStyleSupport.swift`
- Redaction-/Preview-Mutation und Redaction-Restyle aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFAnnotationMutationSupport.swift`
- Dokumentladen, PDF-Ladeergebnisse und Save-Panel-Aufbau aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFDocumentLifecycleSupport.swift`
- Render-Snapshots und Blur-Cache-Zugriff aus `PDFRedactor.swift` liegen jetzt in `HideMyData/PDFPageRenderSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und Bild-Export-Report aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageExportLifecycleSupport.swift`
- OCR-Vorbereitung, Candidate-Aufbau, Schwachtext-Hinweise und Debug-Zusammenstellung aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageDetectionLifecycleSupport.swift`
- Supplemental-Recovery und Sichtbarkeitspruefung aus `ImageRedactor.swift` liegen jetzt in `HideMyData/ImageReviewRecoverySupport.swift`
- Review-/Annotation-Lifecycle fuer Preview-, Dismiss- und Wiederherstellungslogik aus `ImageRedactor.swift` liegt jetzt in `HideMyData/ImageAnnotationReviewLifecycleSupport.swift`
- Hit-Testing, Pending-Auswahl und sichtbare Rect-Zaehlung aus `ImageRedactor.swift` laufen jetzt staerker ueber `HideMyData/ImageAnnotationReviewLifecycleSupport.swift`
- Literal-Suche, Normalisierung und Custom-Pattern-Deduplizierung aus `PatternMatcher.swift` liegen jetzt in `HideMyData/PatternMatcherLiteralSupport.swift`
- Detection-Loop, Regex-/Literal-Span-Aufbau und Diagnostics-Zusammenstellung aus `PatternMatcher.swift` liegen jetzt ebenfalls in `HideMyData/PatternMatcherLiteralSupport.swift`
- Persistenz, Legacy-Migration, Import, Cleanup und Gruppierung aus dem Store-Teil von `PatternMatcher.swift` liegen jetzt in `HideMyData/PatternStorePersistenceSupport.swift` und `HideMyData/PatternStoreManagementSupport.swift`
- Store-Normalisierung, Preview-Expansion, Persisted-Pattern-Sanitizing und Generated-Pattern-Heuristiken aus `PatternMatcher.swift` liegen jetzt ebenfalls in `HideMyData/PatternStoreManagementSupport.swift`
- Bild-Preview-Diagnostik ist in `HideMyData/ImagePreviewDiagnosticsSupport.swift` ausgelagert
- Modellcache- und Platzhalterlogik aus `PIIDetector.swift` ist in `HideMyData/PIIDetectorModelCacheSupport.swift` und `HideMyData/PIIDetectorPlaceholderSupport.swift` verschoben
- sichtbare Pattern-/Custom-Rule-Diagnostik aus `PIIDetector.swift` ist in `HideMyData/PIIDetectorPatternDiagnosticsSupport.swift` ausgelagert
- der größere Span-Sanitizing-/Suppression-Block aus `PIIDetector.swift` liegt jetzt in `HideMyData/PIIDetectorSpanSanitizationSupport.swift`
- Dokumentklassen-Erkennung und Clipboard-Supplemental-Spans aus `PIIDetector.swift` liegen jetzt in `HideMyData/PIIDetectorSupplementalClipboardSupport.swift`
- Review-Kompaktierung und Projection-Logik fuer Trefferbloecke liegen jetzt in `HideMyData/ReviewFindingCompactor.swift`
- Zustandslogik, Fehlermeldungstexte und Persistenz fuer die letzte Zwischenablage-Sitzung aus `PIIDetector.swift` liegen jetzt in `HideMyData/PIIDetectorLifecycleSupport.swift` und `HideMyData/PIIDetectorClipboardSessionSupport.swift`
- Modell-Download, Cache-Load und Ready/Warmup-Orchestrierung aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorLifecycleSupport.swift`
- Warmup-Ausfuehrung und der generische Background-Runner aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorLifecycleSupport.swift`
- Running-Phase und Guard-Verkabelung der oeffentlichen `detect`-API aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorLifecycleSupport.swift`
- Clipboard-Session-Erzeugung, Persistenz-Verkabelung und Restore-Helfer aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorClipboardSessionSupport.swift`
- Modelltreffer-Mapping, Pattern-/Supplemental-Zusammenfuehrung, sichtbare Pattern-Diagnostik und Clipboard-Session-Aufbau aus `PIIDetector.swift` liegen jetzt in `HideMyData/PIIDetectorInferenceSupport.swift`
- Post-Processing-Pipeline, sichtbare Pattern-Diagnostik und der zugehoerige Span-Orchestrierungsblock aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorInferenceSupport.swift`
- Text-Anonymisierung und Clipboard-Anonymisierungsaufbau aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `HideMyData/PIIDetectorAnonymizationSupport.swift`
- die letzten Facade-Helfer `visiblePatternDiagnostics` und `classifyDocumentText` werden jetzt als `PIIDetector`-Extensions aus den jeweiligen Support-Dateien bereitgestellt statt direkt in `PIIDetector.swift`
- `LoadedCustomPattern`, `Diagnostics`, Builtin-Konstante und Entry-Points aus `PatternMatcher.swift` liegen jetzt ebenfalls in `HideMyData/PatternMatcherLiteralSupport.swift`, waehrend `PatternMatcher.swift` im Wesentlichen nur noch den `CustomPatternStore` traegt

## Bekannte Ausgangslage

- sehr geringer Altanteil:
  - `HideMyData/PIIDetector.swift`
  - `HideMyData/PatternMatcher.swift`
  - `HideMyData/Views/Main/MainView.swift`
- merklicher und nun wieder prioritaerer Altanteil:
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
- Auch der technische Rect-Brueckenblock fuer `boundingRects`, `nsRange` und `rectsViaOCRFallback` liegt jetzt in `PDFBoundingRectSupport.swift`, sodass `PDFRedactor` diese Zuordnungslogik nicht mehr direkt traegt.
- Die Erzeugung von Preview-/Blur-/Black-Annotations sowie die Bounds-Normalisierung fuer PDF-Highlights liegt jetzt in `PDFAnnotationStyleSupport.swift`, sodass `PDFRedactor` diesen Styling-Block nicht mehr selbst traegt.
- Auch die eigentliche Mutation fuer Preview-/Redaction-Annotations sowie das Redaction-Restyle liegen jetzt in `PDFAnnotationMutationSupport.swift`, sodass `PDFRedactor` diesen Rebuild-Block nicht mehr direkt traegt.
- Auch Open-/Save-Panel, PDF-Ladeergebnisse und der Render-/Blur-Helferblock liegen jetzt in `PDFDocumentLifecycleSupport.swift` und `PDFPageRenderSupport.swift`, sodass `PDFRedactor` an dieser Lifecycle-Kante weiter Richtung Orchestrierung schürft.

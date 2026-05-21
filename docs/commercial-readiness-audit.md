# Commercial Readiness Audit

Stand: 2026-05-20

## Ziel

Dieses Audit sammelt die noch offenen Punkte fuer eine spaetere Monetarisierung, proprietaere Umstellung oder Mac-App-Store-Distribution.

Es trennt bewusst zwischen:

- rechtlich blockierenden Themen
- sichtbaren oder veroeffentlichten Altspuren
- technischen Resten, die vorerst intern bleiben duerfen

## Aktueller Status

Bereits bereinigt oder ersetzt:

- sichtbare Funding- und Personenreferenzen in aktiven Release-Texten
- Intro-, First-Run- und weitere UI-Bausteine mit hohem Altanteil
- Infrastrukturbausteine wie `ModelDownloader`, `RecentsStore`, `PDFKitView` und `ImageDocumentSurface`
- kleine Modell- und Darstellungsbausteine wie `BlurRedactionAnnotation`, `RedactionStyle+UI` und `InputMode`
- Shared-Modelle fuer `RedactionStyle`, `EditingMode`, Redaction-Workflow-Typen und sicheren Array-Zugriff
- `PDFRedactor` und `ImageRedactor` auf die ausgelagerten Typen umgestellt
- PDF-OCR-Zusatzanalyse fuer Empfaengerkontext in `PDFOCRSupplementalAnalyzer.swift` ausgelagert
- `patterns.json` wird jetzt ueber `PatternMatcherBuiltinSupport.swift` als separaten Manifest-/Compile-Layer geladen, ohne die Regex-Basis zu aendern
- Preview-Diagnostik und Kontext-Rect-Erweiterung fuer PDF-Review laufen jetzt ueber `PDFReviewContextSupport.swift`
- Textquellenwahl, OCR-Bevorzugung und Abschluss-Hinweise fuer PDF-Erkennung laufen jetzt ueber `PDFDetectionLifecycleSupport.swift`
- Seitenweiser Review-Candidate-Aufbau, OCR-Fallback-Zuordnung und Preview-Diagnostik fuer PDF-Erkennung laufen jetzt ueber `PDFDetectionReviewSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und PDF-Export-Report laufen jetzt ueber `PDFExportLifecycleSupport.swift`
- Review-/Annotation-Lifecycle fuer Preview-, Dismiss- und Wiederherstellungslogik laufen jetzt ueber `PDFAnnotationReviewLifecycleSupport.swift`
- Bounding-Rect-Aufloesung, UTF-16-Range-Mapping und OCR-Fallback-Rects fuer PDF-Erkennung laufen jetzt ueber `PDFBoundingRectSupport.swift`
- Annotation-Styling, Preview-Farbgebung und Bounds-Normalisierung fuer PDF-Highlights laufen jetzt ueber `PDFAnnotationStyleSupport.swift`
- Redaction-/Preview-Mutation und Redaction-Restyle laufen jetzt ueber `PDFAnnotationMutationSupport.swift`
- Dokumentladen, PDF-Ladeergebnisse und Save-Panel-Aufbau laufen jetzt ueber `PDFDocumentLifecycleSupport.swift`
- Render-Snapshots und Blur-Cache-Zugriff laufen jetzt ueber `PDFPageRenderSupport.swift`
- Export-Aufbau, Dateinamenvorschlag und Bild-Export-Report laufen jetzt ueber `ImageExportLifecycleSupport.swift`
- OCR-Vorbereitung, Candidate-Aufbau, Schwachtext-Hinweise und Debug-Zusammenstellung fuer Bild-Erkennung laufen jetzt ueber `ImageDetectionLifecycleSupport.swift`
- Supplemental-Recovery und Sichtbarkeitspruefung fuer Bild-Previews laufen jetzt ueber `ImageReviewRecoverySupport.swift`
- Review-/Annotation-Lifecycle fuer Preview-, Dismiss- und Wiederherstellungslogik laufen jetzt ueber `ImageAnnotationReviewLifecycleSupport.swift`
- Literal-Suche, Normalisierung und Custom-Pattern-Deduplizierung laufen jetzt ueber `PatternMatcherLiteralSupport.swift`
- groessere `PIIDetector`-Bloecke fuer Modellcache, Platzhalter, Pattern-Diagnostik, Span-Sanitizing und Clipboard-Supplemente in eigene Support-Dateien verschoben
- PIIDetector-Zustandslogik und die Persistenz der letzten Zwischenablage-Sitzung laufen jetzt ueber `PIIDetectorLifecycleSupport.swift` und `PIIDetectorClipboardSessionSupport.swift`
- PIIDetector-Inferenzaufbau und die sichtbare Pattern-Diagnostik laufen jetzt zusaetzlich ueber `PIIDetectorInferenceSupport.swift`
- Review-Kompaktierung fuer Trefferprojektionen in `ReviewFindingCompactor.swift` ausgelagert
- README-Lizenzhinweis auf den realen Zwischenstand geschaerft
- `.swiftlint.yml` als schlanke eigene Projektkonfiguration neu aufgebaut

## Audit-Refresh 2026-05-21

Aktuelle Groessen der verbleibenden Fachkern-Dateien:

- `HideMyData/PatternMatcher.swift`: `799` Zeilen
- `HideMyData/PDFRedactor.swift`: `609` Zeilen
- `HideMyData/PIIDetector.swift`: `588` Zeilen
- `HideMyData/ImageRedactor.swift`: `522` Zeilen
- `HideMyData/patterns.json`: `352` Zeilen

Neue Priorisierung nach den letzten PDF-Extraktionen:

1. `HideMyData/PatternMatcher.swift`
   Groesster zusammenhaengender Restblock. Enthält weiterhin Store-, Persistenz-, Import-, Cleanup- und Detection-Logik in einer Datei.
2. `HideMyData/patterns.json`
   Nicht gross in Zeilen, aber fachlich sensibel. Die Regex-/Datenbasis selbst bleibt ein relevanter Relicensing-Risikoblock.
3. `HideMyData/PIIDetector.swift`
   Deutlich schlanker, aber immer noch zentraler Integrations- und Orchestrierungsknoten fuer Inferenz, Cache, Placeholder und Post-Processing.
4. `HideMyData/PDFRedactor.swift`
   Nach den neuen Lifecycle-, Rect-, Styling-, Mutations- und Render-Extraktionen inzwischen eher Integrationsklasse mit kleinerem verbleibendem Review-/State-Block.
5. `HideMyData/ImageRedactor.swift`
   Noch relevant, aktuell aber weniger dringlich als `PatternMatcher` und der verbleibende Integrationsrest von `PIIDetector`.

## Rechtlich blockierend

Diese Punkte muessen vor einer proprietaeren oder kommerziellen Umstellung geklaert oder ersetzt sein:

- [LICENSE](../LICENSE)
  Die aktuelle Auslieferung steht weiterhin unter der dort enthaltenen Lizenz.
- Historische Drittbeitraege ohne ausdrueckliche Rechteuebertragung
  Solange diese nicht sicher ersetzt oder lizenziert sind, darf die GPL nicht einfach entfernt werden.
- Verbleibende Fachkern-Dateien mit nicht-trivialen Altanteilen
  Vor allem:
  - [HideMyData/PatternMatcher.swift](../HideMyData/PatternMatcher.swift)
  - [HideMyData/patterns.json](../HideMyData/patterns.json)
  - der verbleibende Integrationsrest in [HideMyData/PIIDetector.swift](../HideMyData/PIIDetector.swift)
  - [HideMyData/PDFRedactor.swift](../HideMyData/PDFRedactor.swift)
  - [HideMyData/ImageRedactor.swift](../HideMyData/ImageRedactor.swift)

## Vor Release oder Store-Vorbereitung bereinigen

Diese Punkte sind nicht zwingend sofort blockierend, sollten aber vor einer breiteren kommerziellen Distribution bereinigt werden:

- [release/sparkle/appcast.xml](../release/sparkle/appcast.xml)
  Historische Enclosure-URL zeigt noch auf altes Distributionsziel.
- [README.md](../README.md)
  Technische Pfade zeigen noch auf den Repo-Ordner `HideMyData/`.
- interne Projekt- und Targetnamen in [Inkognito.xcodeproj/project.pbxproj](../Inkognito.xcodeproj/project.pbxproj)
  Nicht nutzersichtbar, aber fuer spaeteres Packaging und saubere Store-Metadaten relevant.
- Scheme- und Target-Referenzen in [Inkognito.xcodeproj/xcshareddata/xcschemes/Inkognito.xcscheme](../Inkognito.xcodeproj/xcshareddata/xcschemes/Inkognito.xcscheme)

## Kann vorerst intern bleiben

Diese Punkte transportieren derzeit vor allem technische Migration oder Repo-Historie und muessen nicht als Erstes angegangen werden:

- Source-Ordner `HideMyData/`
- Datei [HideMyData/HideMyData.entitlements](../HideMyData/HideMyData.entitlements)
- Legacy-Migrationspfade fuer alte App-Support-Daten
  - [HideMyData/PatternMatcher.swift](../HideMyData/PatternMatcher.swift)
  - [HideMyData/PIIDetector.swift](../HideMyData/PIIDetector.swift)
  - [HideMyData/RecentsStore.swift](../HideMyData/RecentsStore.swift)

## Empfohlene Reihenfolge

1. Rechtekette und verbleibende Drittbeitraege im Fachkern weiter reduzieren.
2. Danach `LICENSE`, README-Lizenztext und Store-Metadaten gemeinsam umstellen.
3. Erst im Anschluss interne Projekt- und Targetnamen offensiv umbenennen, wenn keine Update- oder Packaging-Pfade mehr daran haengen.

## Naechste konkrete Schritte

- `PatternMatcher.swift` als naechsten groessten Fachkern-Block in Store-/Persistenz- und Detection-Verantwortung weiter zerlegen
- `patterns.json` fachlich und datenstrukturell weiter aus dem Altstand herausloesen
- den schlankeren Integrationsrest von `PIIDetector.swift` erneut auf verbleibende Altanteile bewerten
- `PDFRedactor.swift` und `ImageRedactor.swift` erst nach dem Pattern-/PII-Refresh erneut auf weitere sinnvolle Schnitte pruefen
- Sparkle-Historie fuer neue Distribution separat neu aufsetzen
- Lizenzwechsel erst nach Abschluss der technischen und rechtlichen Bereinigung vorbereiten

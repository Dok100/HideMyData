# Commercial Readiness Audit

Stand: 2026-05-21

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
- `Regex-Pattern-Bibliothek.Json` liegt jetzt als validierte Quellbibliothek neben dem Runtime-Manifest; die App laedt weiterhin nur `HideMyData/patterns.json`, das inzwischen ohne die polnischen Regex-Blöcke kuratiert ist, waehrend die Bibliothek die aktuelle Runtime-Teilmenge vollstaendig abdeckt
- `HideMyData/patterns.json` beschreibt seine Runtime-Rolle jetzt selbst ueber Manifest-Metadaten wie `role`, `pattern_count`, `runtime_scope` und die direkte Referenz auf `Regex-Pattern-Bibliothek.Json`, ohne das Laufzeitverhalten zu aendern
- `HideMyData/patterns.json` traegt jetzt ausserdem ein explizites `selection_profile` und dokumentierte `selection_principles`, damit der Runtime-Manifestcharakter auch datenstrukturell klarer vom breiteren Quellenkatalog getrennt bleibt
- `HideMyData/patterns.json` ist jetzt zudem fachlich enger kuratiert: Entwickler-Token- und Krypto-Adressmuster bleiben in der Quellenbibliothek, laufen aber nicht mehr in der App-Runtime mit
- `HideMyData/patterns.json` fuehrt ausserdem keine nicht dokumentzentrierten Secret-/Netzwerkmuster wie IPv4, IPv6, MAC, JWT, US-SSN oder UK-NINO mehr in der Runtime, waehrend diese in der Quellenbibliothek dokumentiert bleiben
- `HideMyData/patterns.json` enthaelt in der Runtime ausserdem keine breiten unlabeled-Kreditkartenmuster mehr; der dokumentzentrierte Kartenfall bleibt ueber `credit_card_labeled` erhalten
- `HideMyData/patterns.json` fuehrt zudem keine breite internationale Telefonnummer ohne Dokument-Label mehr in der Runtime; erhalten bleiben die explizit gelabelten Telefon- und Mobilfelder sowie der dokumentzentrierte MRZ-Fall
- Preview-Diagnostik und Kontext-Rect-Erweiterung fuer PDF-Review laufen jetzt ueber `PDFReviewContextSupport.swift`
- Textquellenwahl, OCR-Bevorzugung und Abschluss-Hinweise fuer PDF-Erkennung laufen jetzt ueber `PDFDetectionLifecycleSupport.swift`
- Seitenweiser Review-Candidate-Aufbau, OCR-Fallback-Zuordnung und Preview-Diagnostik fuer PDF-Erkennung laufen jetzt ueber `PDFDetectionReviewSupport.swift`
- Hit-Testing, Pending-Auswahl sowie Fokus-/Navigationshelfer fuer PDF-Review laufen jetzt staerker ueber `PDFAnnotationReviewLifecycleSupport.swift`, waehrend `PDFRedactor.swift` diese Interaktionen nur noch delegiert
- Hit-Testing, Pending-Auswahl und sichtbare Rect-Zaehlung fuer Bild-Review laufen jetzt staerker ueber `ImageAnnotationReviewLifecycleSupport.swift`, waehrend `ImageRedactor.swift` diese Interaktionen nur noch delegiert
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
- Detection-Loop, Regex-/Literal-Span-Aufbau und Diagnostics-Zusammenstellung aus `PatternMatcher.swift` laufen jetzt ebenfalls ueber `PatternMatcherLiteralSupport.swift`
- Persistenz, Legacy-Migration, Import, Cleanup und Gruppierung fuer benutzerdefinierte Muster laufen jetzt ueber `PatternStorePersistenceSupport.swift` und `PatternStoreManagementSupport.swift`
- Store-Normalisierung, Preview-Expansion, Persisted-Pattern-Sanitizing und Generated-Pattern-Heuristiken aus `PatternMatcher.swift` liegen jetzt ebenfalls in `PatternStoreManagementSupport.swift`
- groessere `PIIDetector`-Bloecke fuer Modellcache, Platzhalter, Pattern-Diagnostik, Span-Sanitizing und Clipboard-Supplemente in eigene Support-Dateien verschoben
- PIIDetector-Zustandslogik und die Persistenz der letzten Zwischenablage-Sitzung laufen jetzt ueber `PIIDetectorLifecycleSupport.swift` und `PIIDetectorClipboardSessionSupport.swift`
- Modell-Download, Cache-Load und Ready/Warmup-Orchestrierung aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorLifecycleSupport.swift`
- Warmup-Ausfuehrung und der generische Background-Runner aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorLifecycleSupport.swift`
- Running-Phase und Guard-Verkabelung der oeffentlichen `detect`-API aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorLifecycleSupport.swift`
- Clipboard-Session-Erzeugung, Persistenz-Verkabelung und Restore-Helfer aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorClipboardSessionSupport.swift`
- PIIDetector-Inferenzaufbau und die sichtbare Pattern-Diagnostik laufen jetzt zusaetzlich ueber `PIIDetectorInferenceSupport.swift`
- Post-Processing-Pipeline, sichtbare Pattern-Diagnostik und der zugehoerige Span-Orchestrierungsblock aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorInferenceSupport.swift`
- Text-Anonymisierung und Clipboard-Anonymisierungsaufbau aus `PIIDetector.swift` laufen jetzt ebenfalls ueber `PIIDetectorAnonymizationSupport.swift`
- die letzten Facade-Helfer `visiblePatternDiagnostics` und `classifyDocumentText` werden jetzt als `PIIDetector`-Extensions aus den jeweiligen Support-Dateien bereitgestellt statt direkt in `PIIDetector.swift`
- `LoadedCustomPattern`, `Diagnostics`, Builtin-Konstante und Entry-Points aus `PatternMatcher.swift` liegen jetzt ebenfalls in `PatternMatcherLiteralSupport.swift`, waehrend `PatternMatcher.swift` im Wesentlichen nur noch den `CustomPatternStore` traegt
- Review-Kompaktierung fuer Trefferprojektionen in `ReviewFindingCompactor.swift` ausgelagert
- README-Lizenzhinweis auf den realen Zwischenstand geschaerft
- `.swiftlint.yml` als schlanke eigene Projektkonfiguration neu aufgebaut

## Audit-Refresh 2026-05-21

Aktuelle Groessen der verbleibenden Fachkern-Dateien:

- `HideMyData/PatternMatcher.swift`: `302` Zeilen
- `HideMyData/PIIDetector.swift`: `303` Zeilen
- `HideMyData/patterns.json`: `188` Zeilen
- `HideMyData/PDFRedactor.swift`: `625` Zeilen
- `HideMyData/ImageRedactor.swift`: `531` Zeilen

Neue Priorisierung nach den letzten Pattern-/PII-Extraktionen:

1. `HideMyData/PDFRedactor.swift`
   Mit `609` Zeilen aktuell wieder der groesste verbleibende fachliche Integrationsknoten; trotz vieler Extraktionen steckt hier der naechste realistisch lohnende Block fuer weiteren Altstands-Abbau.
2. `HideMyData/ImageRedactor.swift`
   Mit `522` Zeilen weiterhin klar ueber den inzwischen stark gestrafften Pattern-/PII-Fassaden und damit der naechste sinnvolle Kandidat nach dem PDF-Pfad.
3. `HideMyData/patterns.json`
   Runtime-Rolle inzwischen sauber dokumentiert und fachlich deutlich enger kuratiert; der verbleibende Risikoblock liegt dort vor allem in der bewussten Restauswahl der dokumentzentrierten Muster.
4. `HideMyData/PIIDetector.swift`
   Inzwischen fast nur noch oeffentliche Fassade und Objektverkabelung; weiterer Nutzen laege eher in Kosmetik als in groessem Fachkern-Abbau.
5. `HideMyData/PatternMatcher.swift`
   Trägt jetzt im Wesentlichen nur noch den `CustomPatternStore`; verbleibender Nutzen läge eher in optionaler Store-Entkopplung als in grossem Fachkern-Abbau.

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

- `PDFRedactor.swift` als naechsten groesseren Integrationsrest erneut auf einen sauberen fachlichen Schnitt pruefen
- `ImageRedactor.swift` danach gegen denselben Massstab bewerten, damit die Priorisierung nicht an den inzwischen stark entschärften Pattern-/PII-Fassaden haengen bleibt
- `patterns.json` fachlich und datenstrukturell weiter aus dem Altstand herausloesen
- den verbleibenden API-/Facade-Rest von `PIIDetector.swift` nur noch dann weiter entkoppeln, wenn sich ein klarer Nutzen ohne Zusatzkomplexitaet ergibt
- den verbleibenden Store-Rest von `PatternMatcher.swift` nur noch dann weiter entkoppeln, wenn sich ein klarer Nutzen ohne Zusatzkomplexitaet ergibt
- die Quellenbibliothek und das Runtime-Manifest weiter bewusst auseinanderhalten und kuenftige Runtime-Streichungen oder Erweiterungen jeweils explizit dokumentieren
- den schlankeren Integrationsrest von `PIIDetector.swift` nur noch begleitend beobachten, statt ihn kuenstlich weiter zu zerlegen
- Sparkle-Historie fuer neue Distribution separat neu aufsetzen
  - vorbereitet als eigener Folgeblock in [features/PROJ-22-sparkle-distribution-reset.md](../features/PROJ-22-sparkle-distribution-reset.md)
- Lizenzwechsel erst nach Abschluss der technischen und rechtlichen Bereinigung vorbereiten

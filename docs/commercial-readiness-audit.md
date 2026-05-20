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
- groessere `PIIDetector`-Bloecke fuer Modellcache, Platzhalter, Pattern-Diagnostik, Span-Sanitizing und Clipboard-Supplemente in eigene Support-Dateien verschoben
- Review-Kompaktierung fuer Trefferprojektionen in `ReviewFindingCompactor.swift` ausgelagert
- README-Lizenzhinweis auf den realen Zwischenstand geschaerft
- `.swiftlint.yml` als schlanke eigene Projektkonfiguration neu aufgebaut

## Rechtlich blockierend

Diese Punkte muessen vor einer proprietaeren oder kommerziellen Umstellung geklaert oder ersetzt sein:

- [LICENSE](../LICENSE)
  Die aktuelle Auslieferung steht weiterhin unter der dort enthaltenen Lizenz.
- Historische Drittbeitraege ohne ausdrueckliche Rechteuebertragung
  Solange diese nicht sicher ersetzt oder lizenziert sind, darf die GPL nicht einfach entfernt werden.
- Verbleibende Fachkern-Dateien mit nicht-trivialen Altanteilen
  Vor allem:
  - [HideMyData/patterns.json](../HideMyData/patterns.json)
  - [HideMyData/PDFRedactor.swift](../HideMyData/PDFRedactor.swift)
  - [HideMyData/ImageRedactor.swift](../HideMyData/ImageRedactor.swift)
  - Teile von [HideMyData/PIIDetector.swift](../HideMyData/PIIDetector.swift), die trotz der bereits erfolgten Extraktionen noch nicht separat neu bewertet wurden

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

- `patterns.json` fachlich und datenstrukturell weiter aus dem Altstand herausloesen
- `PDFRedactor.swift` und `ImageRedactor.swift` weiter modularisieren, damit verbleibende Altanteile gezielt ersetzbar werden
- den Restkern von `PIIDetector.swift` nach den neuen Support-Extraktionen erneut auf verbleibende Altanteile bewerten
- Sparkle-Historie fuer neue Distribution separat neu aufsetzen
- Lizenzwechsel erst nach Abschluss der technischen und rechtlichen Bereinigung vorbereiten

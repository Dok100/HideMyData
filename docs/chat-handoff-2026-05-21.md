# Chat Handoff 2026-05-21

Nutze diesen Prompt als Startpunkt fuer den naechsten Chat:

```text
Wir arbeiten im Repo /Users/oliverkern/Documents/Projekte/HideMyData auf dem Branch codex-conjoined-name-pdf-fixes.

Bitte uebernimm den aktuellen Stand von HEAD.

Kontext:
- PROJ-21 Commercial Readiness und Re-Licensing Cleanup laeuft weiter
- PROJ-22 behandelt den Sparkle-Distributionsreset separat
- PROJ-23 schaerft Onboarding- und Regeln-Editor-UX nach
- Der Runtime-Manifeststand in HideMyData/patterns.json ist bewusst enger kuratiert als die Quellenbibliothek Regex-Pattern-Bibliothek.Json
- PIIDetector.swift und PatternMatcher.swift sind inzwischen nur noch schlanke Fassaden und sollen nur noch bei klarem Mehrwert weiter entkoppelt werden

Wichtige zuletzt erledigte Punkte:
- PDF-Review-Interaktionen weiter nach PDFAnnotationReviewLifecycleSupport.swift delegiert
- Bild-Review-Interaktionen weiter nach ImageAnnotationReviewLifecycleSupport.swift delegiert
- patterns.json traegt jetzt zusaetzliche Runtime-Metadaten wie selection_profile und selection_principles
- Intro-/Onboarding-Texte benennen jetzt Anonymisierung von Dateien, PDFs, Bildern und Zwischenablage klarer
- Der Regeln-Editor hat jetzt unten eine feste Aktionsleiste, damit Nutzer nicht fuer "Fertig" nach oben zurueckscrollen muessen
- Sparkle-Historie ist bewusst als separater Folgeblock in features/PROJ-22-sparkle-distribution-reset.md dokumentiert

Letzte Verifikation:
- swift scripts/run_detection_regressions.swift -> Detection regressions passed (202 checks)
- xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build -> BUILD SUCCEEDED

Aktuelle Audit-Priorisierung:
1. HideMyData/PDFRedactor.swift
2. HideMyData/ImageRedactor.swift
3. HideMyData/patterns.json
4. HideMyData/PIIDetector.swift
5. HideMyData/PatternMatcher.swift

Naechste sinnvolle Schritte:
1. PDFRedactor.swift erneut auf den naechsten sauberen fachlichen Schnitt pruefen
2. Danach ImageRedactor.swift gegen denselben Massstab bewerten
3. patterns.json weiter bewusst als Runtime-Manifest gegen die Quellenbibliothek kuratieren
4. PIIDetector.swift und PatternMatcher.swift nur noch bei klarem Nutzen weiter entkoppeln
5. Sparkle-Reset separat ueber PROJ-22 behandeln, nicht nebenbei in laufenden Cleanup-Schritten vermischen

Bitte vorsichtig weiterarbeiten, bestehendes Verhalten nicht kaputt machen und nach Codeaenderungen wieder mit Regressionen und Build verifizieren.
```

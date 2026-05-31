# Chat Handoff 2026-05-21

Nutze diesen Prompt als Startpunkt fuer den naechsten Chat:

```text
Wir arbeiten im Repo /Users/oliverkern/Documents/Projekte/Inkognito auf dem Branch codex-conjoined-name-pdf-fixes.

Bitte uebernimm den aktuellen Stand von HEAD.

Kontext:
- PROJ-21 Commercial Readiness und Re-Licensing Cleanup ist abgeschlossen
- PROJ-22 behandelt den Sparkle-Distributionsreset separat
- PROJ-23 schaerft Onboarding- und Regeln-Editor-UX nach
- Der Runtime-Manifeststand in Inkognito/patterns.json ist bewusst enger kuratiert als die Quellenbibliothek Regex-Pattern-Bibliothek.Json
- PIIDetector.swift und PatternMatcher.swift sind inzwischen nur noch schlanke Fassaden und sollen nur noch bei klarem Mehrwert weiter entkoppelt werden
- Das bisherige Fork-Repository bleibt als Nachschlagewerk; `Dok100/Inkognito` ist die neue Produktbasis

Wichtige zuletzt erledigte Punkte:
- PDF-Review-Interaktionen weiter nach PDFAnnotationReviewLifecycleSupport.swift delegiert
- PDF-Preview-zu-Redaction- und Accepted-zu-Pending-Uebergaenge weiter nach PDFAnnotationReviewLifecycleSupport.swift delegiert
- Bild-Review-Interaktionen weiter nach ImageAnnotationReviewLifecycleSupport.swift delegiert
- patterns.json traegt jetzt zusaetzliche Runtime-Metadaten wie selection_profile und selection_principles
- patterns.json dokumentiert jetzt bewusst behaltene Runtime-Grenzfaelle zusaetzlich ueber retained_runtime_notes
- Intro-/Onboarding-Texte benennen jetzt Anonymisierung von Dateien, PDFs, Bildern und Zwischenablage klarer
- Der Regeln-Editor hat jetzt unten eine feste Aktionsleiste, damit Nutzer nicht fuer "Fertig" nach oben zurueckscrollen muessen
- Sparkle-Historie ist bewusst als separater Folgeblock in features/PROJ-22-sparkle-distribution-reset.md dokumentiert

Letzte Verifikation:
- swift scripts/run_detection_regressions.swift -> Detection regressions passed (202 checks)
- xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build -> BUILD SUCCEEDED

Aktuelle Audit-Priorisierung:
1. Inkognito/PDFRedactor.swift
2. Inkognito/ImageRedactor.swift
3. Inkognito/patterns.json
4. Inkognito/PIIDetector.swift
5. Inkognito/PatternMatcher.swift

Naechste sinnvolle Schritte:
1. Neue Produkt- und Release-Arbeit bevorzugt im Repository `Dok100/Inkognito` weiterfuehren
2. Sparkle-Reset separat ueber PROJ-22 behandeln, nicht nebenbei in laufenden Cleanup-Schritten vermischen
3. Dieses Repository vor allem als Nachschlagewerk und Referenz fuer Herkunft, Regressionen und Architekturentscheidungen nutzen

Bitte vorsichtig weiterarbeiten, bestehendes Verhalten nicht kaputt machen und nach Codeaenderungen wieder mit Regressionen und Build verifizieren.
```

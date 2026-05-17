# PROJ-1 – Detection-Härtung

**Status**: Abgeschlossen

## Ziel

Die Erkennung soll über OCR, nativen PDF-Text und Bilder hinweg reproduzierbar und dokumenttypübergreifend stabil werden.

## Schwerpunkte

- mehr anonymisierte Fixtures je Dokumenttyp
- Regression-Suite mit Soll-/Nicht-Soll-Treffern
- klar getrennte Problemklassen: Namen, Adressen, Bankdaten, Behördenköpfe, OCR-Zerfall
- besserer Diagnosepfad für verworfene Treffer

## Deliverables

- erweiterter `fixtures/detection/`-Bestand
- ausgebautes `scripts/run_detection_regressions.swift`
- einfache Testmatrix pro Dokumentklasse
- dokumentierte Qualitätsziele pro Klasse

## Abschlussstand

- Detection ist ueber native PDFs, OCR/Bilder und den Zwischenablage-Pfad repo-tauglich gehaertet.
- Die Regression-Suite deckt die relevanten Dokumentklassen und die wichtigsten Blindspots aus PROJ-1 ab.
- Der Clipboard-/Platzhalterpfad anonymisiert und fuehrt funktional stabil zurueck; verbleibende Restpunkte sind kosmetischer Natur und blockieren PROJ-1 nicht mehr.

## Nicht-blockierende Restpunkte

- Platzhalter-Terminologie im Clipboard-Export kann in Einzelfaellen noch produktsprachlich sauberer werden.
- Einzelne Formatdetails im Zwischenablage-Preview koennen spaeter in Folgeprojekten geglaettet werden.

## Relevante Dateien

- `fixtures/detection/`
- `scripts/run_detection_regressions.swift`
- `HideMyData/PIIDetector.swift`
- `HideMyData/patterns.json`

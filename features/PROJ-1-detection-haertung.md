# PROJ-1 – Detection-Härtung

**Status**: Geplant

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

## Relevante Dateien

- `fixtures/detection/`
- `scripts/run_detection_regressions.swift`
- `HideMyData/PIIDetector.swift`
- `HideMyData/patterns.json`


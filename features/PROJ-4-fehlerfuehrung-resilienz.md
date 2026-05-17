# PROJ-4 – Fehlerführung und Resilienz

**Status**: Geplant

## Ziel

Inkognito soll auch bei schlechten Eingaben, OCR-Problemen oder Modellfehlern ruhig und verständlich reagieren.

## Schwerpunkte

- verständlichere Fehlermeldungen
- Retry- und Fallback-Flows
- robuste Zustände für ungeeignete PDFs oder leere Eingaben
- klarere Hinweise bei Modell-/Downloadproblemen

## Deliverables

- Fehlertext-Review
- definierte Zustände für OCR-/PDF-Fallbacks
- Retry-Komponenten an neuralgischen Stellen
- bessere Leer-/Fehlerzustände

## Relevante Dateien

- `HideMyData/ContentView.swift`
- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PIIDetector.swift`


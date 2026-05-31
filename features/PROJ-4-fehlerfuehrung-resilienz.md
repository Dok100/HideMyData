# PROJ-4 – Fehlerführung und Resilienz

**Status**: In Arbeit

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

## Umgesetzt im ersten Block

- ruhige, verständliche Öffnen-Fehler für PDFs und Bilder statt stiller Fehlschläge
- Retry-Dialoge für fehlgeschlagene Öffnen-Aktionen und ungültige Einträge aus `Zuletzt verwendet`
- klarer Hinweis bei ungeeigneten Drag-and-drop-Dateien
- verständliche Export-/Speicherfehler mit Wiederholen-Aktion statt generischem Fehlschlag
- produktisierte Zustände für `Kaum lesbarer Text im PDF`, `OCR nur teilweise brauchbar`, `Kaum lesbarer Text im Bild` und `OCR-Ergebnis sehr schwach`
- ruhigere Status-Banner im Clipboard-Flow bei leerer Zwischenablage, fehlgeschlagener Anonymisierung und `nichts gefunden`
- weniger technische Fehltexte im Modell-Download- und Ladepfad

## Relevante Dateien

- `Inkognito/ContentView.swift`
- `Inkognito/Views/Main/MainView.swift`
- `Inkognito/PIIDetector.swift`
- `Inkognito/PDFRedactor.swift`
- `Inkognito/ImageRedactor.swift`
- `Inkognito/Views/Main/DocumentSurface.swift`
- `Inkognito/Views/Main/ImageDocumentSurface.swift`
- `Inkognito/Views/Toolbar/FloatingToolbar.swift`

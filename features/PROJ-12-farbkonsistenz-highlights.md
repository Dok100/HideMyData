# PROJ-12 – Farbkonsistenz zwischen Legende und Highlights

**Status**: Abgeschlossen

## Ziel

Die in der Legende kommunizierten Farben müssen exakt mit Sidebar-Karten und Dokument-Highlights übereinstimmen.

## Schwerpunkte

- Sidebars, Badges und PDF-/Bild-Overlays auf dieselben Farbwerte bringen
- visuelle Screenshot-Prüfung
- keine abweichenden Einzeldefinitionen pro View

## Deliverables

- zentrale Farbreferenz
- bereinigte Highlight-Farben
- visuelle Abnahme anhand realer Dokumente

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`

## Umsetzung

- Die Farblogik für Kategorien und Vorschau-Highlights wurde zentral in `FindingVisualSemantics` gebündelt.
- Manuelle Zieh-Vorschauen in PDF- und Bild-Ansicht verwenden jetzt dieselbe zentrale Preview-Farbe statt lokaler Rot-/Adress-Fallbacks.
- Damit stimmen Legende, Finding-Farben und Dokument-Highlights wieder auf derselben Referenzbasis überein.

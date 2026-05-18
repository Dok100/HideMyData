# PROJ-5 – Farbsystem und visuelle Konsistenz

**Status**: Abgeschlossen

## Ziel

Legende, Sidebar, Dokument-Highlights und Statusflächen sollen sich wie ein einheitliches, bewusstes Farbsystem anfühlen.

## Schwerpunkte

- zentrale Farbdefinition je Kategorie
- konsistente Nutzung in Listen, Karten und Overlays
- Abgleich von Legende und tatsächlichen Highlight-Farben
- kleiner interner UI-Styleguide

## Deliverables

- zentrale Category-Color-Zuordnung
- bereinigte UI-Verwendung in allen Hauptscreens
- dokumentierte Farbsemantik

## Umgesetzt im ersten Block

- zentrale Farbsemantik für Personen, Adressen, Nummern, Kontakt, Datum und E-Mail
- Sidebar-Legende aus derselben Quelle wie die tatsächlichen Dokument-Highlights
- gemeinsame Category-Zuordnung für PDF-Preview, Bild-Preview und Review-Karten
- vereinheitlichte Kategorienamen für Legende und Finding-Kacheln

## Umgesetzt im zweiten Block

- harmonisierte Status-Tonfamilie für Erfolg, Vertrauen und Aufmerksamkeit
- `StatusPill`, Review-Abschlusskarte, Undo-Banner und Export-Vertrauenskarte folgen jetzt denselben Grundtönen
- konsistentere Wirkung zwischen Sidebar-Status und globalen Statusflächen

## Umgesetzt im dritten Block

- neutrale Flächensemantik für Toolbar, Sidebar, Step-Strip, Navigation und Empty-State-Karten
- weniger abweichende Einzelgrautöne zwischen Hauptflächen und Hilfsflächen
- konsistentere Panel-, Karten- und Kapselränder über die wichtigsten Screens hinweg

## Umgesetzt im vierten Block

- Source- und Status-Badges in den Review-Karten nutzen jetzt dieselbe zentrale Farbsemantik wie die übrigen Statusflächen
- keine lokalen Blau/Mint/Orange- oder Grün/Rot-Sonderfälle mehr in den Finding-Karten
- konsistentere Wirkung zwischen Review-Liste, Status-Pills, Abschlusskarte und Export-Vertrauensmodul

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`
- `HideMyData/BlackRedactionAnnotation.swift`
- `HideMyData/Views/Status/StatusPill.swift`
- `HideMyData/Views/Toolbar/FloatingToolbar.swift`
- `HideMyData/Views/Toolbar/GlassSegmented.swift`
- `HideMyData/Views/Main/EmptyState.swift`

# Decision Log

## 2026-05-16

- `PROJ-1` wird als abgeschlossen gewertet.
- Die Detection-Haertung gilt fuer native PDFs, OCR/Bilder und den Clipboard-/Platzhalterpfad als funktional stabil.
- Nicht-blockierende Restpunkte aus dem Clipboard-Preview werden nicht mehr in `PROJ-1`, sondern spaeter als Produktfeinschliff behandelt.

## 2026-05-13

- `Inkognito.xcodeproj` ist das aktive Projekt.
- Das alte `HideMyData.xcodeproj` wird nur noch archiviert und nicht mehr aktiv gepflegt.
- Die GitHub-CI baut direkt `Inkognito.xcodeproj`, statt ueber `xcodegen` ein Legacy-Projekt zu verifizieren.
- Feature-Planung lebt in `features/` nach einem projektweisen Format, angelehnt an Dicto.
- Historische Generator- und Icon-Arbeitsordner werden archiviert, nicht im aktiven Projektpfad weitergefuehrt.

## Offene Architekturentscheidungen

- Soll die Diagnose-View einen expliziten Developer-Modus erhalten?
- Sollen Dokumentklassen intern frueh klassifiziert werden oder zunaechst nur heuristisch?
- Soll die Export-Validierung spaeter automatisiert pruefbar werden?

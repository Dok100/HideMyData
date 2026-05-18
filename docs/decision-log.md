# Decision Log

## 2026-05-16

- `PROJ-1` wird als abgeschlossen gewertet.
- Die Detection-Haertung gilt fuer native PDFs, OCR/Bilder und den Clipboard-/Platzhalterpfad als funktional stabil.
- Nicht-blockierende Restpunkte aus dem Clipboard-Preview werden nicht mehr in `PROJ-1`, sondern spaeter als Produktfeinschliff behandelt.
- `PROJ-2` startet mit einem technischen Export-Validierungsreport fuer PDF- und Bildexporte.
- Export-Vertrauen wird nicht nur ueber Text, sondern ueber konkrete technische Aussagen zu eingebrannten Schwärzungen, annotationsfreiem Export und Metadaten-Bereinigung kommuniziert.
- `PROJ-2` wird als abgeschlossen gewertet.
- Ein explizites Exportprotokoll oder ein vertiefter Validierungsdialog bleibt optionaler Produktfeinschliff und ist kein Release-Blocker.
- `PROJ-3` wird als abgeschlossen gewertet.
- Der Review-Workflow gilt mit Statuslogik, Ruecknahme, direktem Fokus-Sprung aus sichtbaren Schwärzungen und exportorientiertem Abschlussmoment als funktional stabil.
- Bei aktivem Filter `Nur offene Treffer` bleibt ein ueber die Dokumentflaeche fokussierter bestaetigter oder abgelehnter Treffer sichtbar, damit Korrekturen ohne Filterwechsel moeglich bleiben.
- `PROJ-5` wird als abgeschlossen gewertet.
- Das Farbsystem gilt fuer Kategorien, Statusflächen, Review-Karten und neutrale Hauptflächen als zentralisiert und konsistent genug fuer den aktiven Produktstand.

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

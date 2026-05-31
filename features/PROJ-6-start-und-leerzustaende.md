# PROJ-6 – Start- und Leerzustände

**Status**: Abgeschlossen

## Ziel

Der Einstieg in die App soll sofort verständlich sein und die zwei Hauptworkflows gleichwertig kommunizieren.

## Bereits umgesetzt

- klarerer Modus-Text (`Format: PDF/Bild`)
- sichtbarer Drag-and-Drop-Bereich
- gleichwertigere Button-Hierarchie
- stärkerer Abschlusszustand in der Review-Sidebar
- handlungsorientierterer Startzustand mit klareren Einstiegen für Dokument und Zwischenablage
- reduzierte Meta-Texte im Empty State und im Clipboard-Einstieg
- konsistentere Formulierungen zwischen Dokument-Start und Clipboard-Flow
- vereinheitlichte Leerzustände im Clipboard-Sheet für `noch nichts geladen`, `noch keine Vorschau`, `noch keine Platzhalter`, `noch keine Rückführung` und `noch kein Mapping`
- `Zuletzt verwendet` bleibt auch ohne Einträge als ruhiger, erklärter Startbereich sichtbar

## Relevante Dateien

- `Inkognito/Views/Main/EmptyState.swift`
- `Inkognito/Views/Main/MainView.swift`

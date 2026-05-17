# PROJ-3 – Review-Workflow

**Status**: Abgeschlossen

## Ziel

Treffer prüfen, bestätigen und ablehnen soll klar, schnell und fehlertolerant funktionieren.

## Schwerpunkte

- Statuslogik für `offen`, `bestätigt`, `abgelehnt`
- sicherere Sammelaktionen
- Undo-/Rücknahme-Optionen
- stärkerer Abschlussmoment vor dem Speichern

## Deliverables

- überarbeitete Sidebar-Interaktion
- klarere CTA-Hierarchie
- definierte Aktionen für Einzel- und Massenbestätigung
- optionaler Rückgängig-Flow

## Stand 2026-05-17

- Sidebar zeigt jetzt alle drei Zustände `offen`, `bestätigt` und `abgelehnt`
- Sammelbestätigung kommuniziert explizit, wie viele offene Treffer bestätigt werden
- Einzelne Treffer können nach `bestätigt` oder `abgelehnt` wieder auf `offen` zurückgesetzt werden
- Klick auf eine sichtbare Schwärzung oder Preview fokussiert jetzt die zugehörige Review-Kachel direkt in der Sidebar
- Bei gruppierten Treffern priorisiert der Klick jetzt den kleinsten passenden Treffer statt eines zu breiten Blocks
- Abschlussmoment wurde stärker auf sicheren Export ausgerichtet, inklusive direkter Save-CTA nach fertigem Review
- Entscheidungen zeigen jetzt einen direkten Undo-Hinweis in der Sidebar
- Toolbar bietet einen sichtbaren `Einstellungen`-Zugang für Erscheinungsbild und Datenschutz
- Bei aktivem Filter `Nur offene Treffer` bleibt ein per Klick fokussierter bestätigter oder abgelehnter Treffer trotzdem sichtbar, damit er direkt wieder geöffnet werden kann
- Die Abschlusskarte in der Sidebar ist auf schmalerer Breite stabil lesbar und schneidet Titel oder Save-CTA nicht mehr ab

## Bekannter Feinschliff

- optional prüfen, ob die Trefferauswahl bei sehr nahen Überlappungen zusätzlich nach Textzeilen-Passung priorisiert werden soll
- optional prüfen, ob der Undo-Hinweis später als temporärer Toast statt nur in der Sidebar erscheinen soll

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`
- `HideMyData/PDFKitView.swift`
- `HideMyData/Views/Main/ImageDocumentSurface.swift`
- `HideMyData/Views/Toolbar/FloatingToolbar.swift`

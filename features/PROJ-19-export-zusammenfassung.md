# PROJ-19 – Menschliche Export-Zusammenfassung

**Status**: Abgeschlossen

## Ziel

Vor oder nach dem Export soll eine kurze, verständliche Sicherheitszusammenfassung das Vertrauen in das Ergebnis stärken.

## Schwerpunkte

- Anzahl geschützter Stellen knapp zusammenfassen
- schwache Seiten oder manuelle Eingriffe sichtbar machen
- technische Prüfwerte in verständliche Sprache übersetzen

## Deliverables

- kompakte Export-Zusammenfassung
- klare Vertrauenshinweise für Menschen statt reine Diagnosedaten
- besserer Übergang von Review zu Export

## Relevante Dateien

- `Inkognito/Views/Main/MainView.swift`
- `Inkognito/PDFRedactor.swift`
- `Inkognito/ImageRedactor.swift`
- Export-Validierungslogik

## Umsetzung

- Vor dem Export zeigt die Review-Sidebar jetzt eine kurze menschliche Zusammenfassung mit Anzahl der Schutzstellen, manuellen Ergänzungen und Hinweisen auf schwächere Textqualität.
- Nach dem Speichern nutzt der Export-Report nicht mehr nur technische Statussätze, sondern eine verständliche Zusammenfassung mit geschützten Stellen, manuellen Eingriffen, Textqualitätswarnungen und den bestehenden Export-Sicherheiten.
- PDF- und Bildexport melden dafür jetzt zusätzlich, wie viele manuelle Schwärzungen enthalten waren und ob bereits vor dem Export schwächere Textqualität erkannt wurde.

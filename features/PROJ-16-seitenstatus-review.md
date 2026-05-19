# PROJ-16 – Seitenstatus im Review

**Status**: Abgeschlossen

## Ziel

Der Review soll nicht nur einzelne Treffer, sondern den Prüfstatus ganzer Seiten verständlich machen.

## Schwerpunkte

- Seitenstatus wie `offen`, `geprüft`, `wenig lesbarer Text` oder `besonders prüfen`
- klare Sicht, welche Seiten noch Aufmerksamkeit brauchen
- Brücke zwischen Trefferliste, Dokumentnavigation und Exportvertrauen

## Deliverables

- sichtbarer Seitenstatus im Review
- kompakte Seitenübersicht mit Priorisierung
- einfache Regeln für automatische Seitenwarnungen

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`

## Umsetzung

- Review-Sidebar zeigt jetzt einen kompakten Seitenstatus vor der Trefferliste.
- Seiten werden mit einfachen Regeln automatisch als `offen`, `geprüft`, `besonders prüfen`, `wenig lesbarer Text` oder `keine Treffer` markiert.
- PDFs nutzen die echte Seitenzahl; Bilder werden als einseitiger Review-Fall behandelt.
- Wenn die Erkennung bereits auf schwachen Text oder OCR-Probleme hinweist, erscheint das auch in der Seitenübersicht.

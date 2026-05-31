# PROJ-17 – Unsicherheiten und Auffälligkeiten bündeln

**Status**: Abgeschlossen

## Ziel

Unsichere oder ungewöhnliche Treffer sollen gesondert sichtbar werden, statt in normalen Vorschlägen unterzugehen.

## Schwerpunkte

- schwache OCR-Seiten gesondert kennzeichnen
- ungewöhnliche Trefferkontexte markieren
- niedrige Modell-Sicherheit oder juristische Grenzfälle bündeln

## Deliverables

- sichtbare Unsicherheits-Hinweise im Review
- nachvollziehbare Kriterien fuer `besonders pruefen`
- produktnahe Hinweise statt technischer Fehlersprache

## Relevante Dateien

- `Inkognito/PIIDetector.swift`
- `Inkognito/PDFRedactor.swift`
- `Inkognito/ImageRedactor.swift`
- `Inkognito/Views/Main/MainView.swift`

## Umsetzung

- Schwacher Text, unsichere offene Treffer, Personenseiten und besonders pruefenswerte Seiten werden im Review sichtbar gemacht, ohne dass sie in normalen Treffern untergehen.
- Nach dem UI-Feinschliff sitzen die wichtigsten Unsicherheits-Hinweise direkt an den betroffenen Review-Karten oder kompakten Seitenhinweisen, statt eine grosse Meta-Ebene vor die Trefferliste zu setzen.
- Die Hinweise bleiben absichtlich produktnah formuliert und nennen konkrete Pruefgruende statt technischer Modellbegriffe.

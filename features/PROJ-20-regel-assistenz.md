# PROJ-20 – Regel-Assistenz und Vorlagen

**Status**: Abgeschlossen

## Ziel

Eigene Regeln sollen nicht nur editierbar, sondern aktiv verständlich und produktiv unterstützend werden.

## Schwerpunkte

- Vorlagen für Namen, Adressen, Kennungen und Dokumentfelder
- Hinweise bei zu allgemeinen oder schwachen Regeln
- bessere Vorschau, was eine Regel im Dokument tatsächlich treffen würde

## Deliverables

- kleine Vorlagenbibliothek
- Qualitätsindikatoren für Regeln
- verständlichere Test- und Vorschauhilfen

## Relevante Dateien

- `Inkognito/Views/Main/MainView.swift`
- `Inkognito/PatternMatcher.swift`
- `Inkognito/PIIDetector.swift`
- Feature-Doku für eigene Regeln

## Umsetzung

- Der Regeln-Editor zeigt jetzt zusätzliche Qualitätsindikatoren für zu kurze, wenig trennscharfe oder sehr stark abgeleitete Eingaben.
- Aus der aktuellen Eingabe wird direkt eine kleine Dokumentvorschau erzeugt, die zeigt, welche Textstellen im gerade geöffneten Dokument getroffen würden.
- Wenn die aktuelle Regel im Dokument noch keine klare Textstelle trifft, macht Inkognito das vor dem Speichern sichtbar.

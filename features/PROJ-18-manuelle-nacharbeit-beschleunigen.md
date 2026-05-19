# PROJ-18 – Manuelle Nacharbeit beschleunigen

**Status**: Abgeschlossen

## Ziel

Wiederkehrende Korrekturen sollen schneller gehen, damit Inkognito auch bei Grenzfällen effizient bleibt.

## Schwerpunkte

- ähnliche Treffer leichter gemeinsam bearbeiten
- aus manuellen Entscheidungen schneller neue Regeln ableiten
- Mehrfacharbeit bei Namensvarianten und Wiederholungen reduzieren

## Deliverables

- erste Sammelaktionen oder Ähnlichkeitsvorschläge
- schnellere Folgeaktionen nach `Bestätigen` oder `Ablehnen`
- klarer produktnaher Flow für manuelle Korrekturen

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`
- `HideMyData/PatternMatcher.swift`

## Umsetzung

- Offene Treffer zeigen jetzt direkt in der Detailansicht, wenn identische ähnliche Stellen ebenfalls noch offen sind.
- Diese ähnlichen Stellen lassen sich gesammelt bestätigen oder ablehnen, statt jede Wiederholung einzeln zu bearbeiten.
- Die erste Version arbeitet bewusst konservativ mit gleicher Kategorie und normalisiert gleichem Textausschnitt.

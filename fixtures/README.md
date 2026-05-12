# Fixtures

Dieses Verzeichnis trennt bewusst zwischen zwei Arten von Testmaterial:

- `fixtures/detection/`: anonymisierte, synthetische oder explizit repo-taugliche Text-Fixtures fuer Regression-Checks
- `fixtures/private/`: lokale, nicht versionierte Beispiele mit echten oder sensiblen Inhalten

## Regeln

- Alles unter `fixtures/detection/` muss vor einem Commit anonymisiert sein.
- Echte PDFs, OCR-Ausgaben oder sensible Rohtexte gehoeren nur nach `fixtures/private/`.
- `fixtures/private/` ist in `.gitignore` eingetragen und wird nicht nach GitHub gepusht.

## Hintergrund

Die Detection-Regressionen in `scripts/run_detection_regressions.swift` greifen bewusst nur auf repo-taugliche Fixtures aus `fixtures/detection/` zu. So bleiben die Tests reproduzierbar, ohne vertrauliche Beispieldaten in die Versionsverwaltung zu bringen.

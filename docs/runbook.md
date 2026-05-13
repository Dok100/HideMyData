# Runbook

## Lokaler Build

```bash
xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build
```

## Regressionen

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift
```

## Typische Wartungsfaelle

### Neues Detection-Problem aus echter Datei

1. anonymisierte Fixture erzeugen
2. Regression in `scripts/run_detection_regressions.swift` ergaenzen
3. Heuristik oder Pattern anpassen
4. Build und Regressionen erneut laufen lassen

### UI-/Terminologie-Inkonsistenz

1. betroffene View identifizieren
2. pruefen, ob es schon zentrales Mapping/Farbsystem gibt
3. Text/Farbe/Status an zentraler Stelle bereinigen

### Neue Icons

Das aktive App-Icon liegt in:

- `HideMyData/Assets.xcassets/AppIcon.appiconset`

Historische Generatoren und Arbeitsdateien sind archiviert.

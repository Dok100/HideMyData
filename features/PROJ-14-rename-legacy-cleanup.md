# PROJ-14 – Rename- und Legacy-Cleanup (`HideMyData` -> `Inkognito`)

**Status**: Geplant

## Ziel

Historische Namensreste von `HideMyData` sollen kontrolliert aus dem aktiven Projekt entfernt oder bewusst archiviert werden, ohne Release-Pfade, Legacy-Migrationen oder Build-Konfigurationen unbeabsichtigt zu brechen.

## Schwerpunkte

- aktiven Projektpfad konsequent auf `Inkognito` ausrichten
- alte Ordner- und Target-Bezeichnungen bewerten
- Legacy-Dateien im `release/`- und Sparkle-Bereich bewusst behandeln
- historische Migrationspfade nur dort behalten, wo sie fuer bestehende Nutzer technisch noch gebraucht werden

## Wichtige Vorsichtspunkte

- `release/sparkle/HideMyData-0.2.0.html` und `appcast.xml` nicht blind umbenennen, solange historische Update-Pfade noch relevant sein koennten
- alte Container-/UserDefaults-/Cache-Migrationslogik nur entfernen, wenn sie fuer Bestandsnutzer nicht mehr benoetigt wird
- Xcode-/Target-/Scheme-Renames getrennt von reinem Datei-Cleanup behandeln

## Deliverables

- Liste `aktiv behalten / archivieren / spaeter umbenennen`
- Bereinigung offensichtlicher Legacy-Reste im aktiven Projekt
- separates, sicheres Rename-Konzept fuer Code, Ordner, Projekt und Release-Artefakte
- optional ein finaler Schritt fuer die Umbenennung des Source-Ordners `HideMyData/`

## Relevante Dateien

- `HideMyData/`
- `Inkognito.xcodeproj`
- `README.md`
- `CHANGELOG.md`
- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- Legacy-Migrationslogik in App- und Storage-Dateien

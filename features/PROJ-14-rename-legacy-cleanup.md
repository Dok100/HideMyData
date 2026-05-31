# PROJ-14 – Rename- und Legacy-Cleanup (`HideMyData` -> `Inkognito`)

**Status**: Abgeschlossen

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
- optional ein finaler Schritt fuer die Umbenennung des Source-Ordners `Inkognito/`

## Relevante Dateien

- `Inkognito/`
- `Inkognito.xcodeproj`
- `README.md`
- `CHANGELOG.md`
- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- Legacy-Migrationslogik in App- und Storage-Dateien

## Bewertung

### Aktiv behalten

- Legacy-Migrationspfade fuer Container, Cache, Recents und Clipboard-Session
- Sparkle-Historie in `release/sparkle/`, solange alte Artefaktnamen noch fuer Bestandsupdates relevant sein koennen

### Bereinigt

- aktiver App-Einstieg intern auf `InkognitoApp` umgestellt
- App-Einstiegsdatei im aktiven Projekt auf `InkognitoApp.swift` umgestellt
- aktives Entitlements-File auf `Inkognito.entitlements` umgestellt
- neue App-Notification fuer die Zwischenablage auf `Inkognito.showClipboardAnonymizer` umgestellt
- Legacy-Notification `HMD.showClipboardAnonymizer` vorerst als Fallback weiter akzeptiert
- Xcode-Target- und Scheme-Metadaten intern auf `Inkognito` umgestellt
- aktiver Source-Ordner auf `Inkognito/` umgezogen

### Später umbenennen

- keine aktiven Source-Pfad-Reste mehr; nur historische Release- und Migrationspfade bleiben bewusst bestehen

## Umsetzung

- Historische Sparkle-Artefakte wurden bewusst nicht angerührt.
- Aktive Legacy-Reste wurden in `technisch nötig` und `später separat migrieren` getrennt.
- Nur intern ungefährliche Bezeichner im laufenden App-Pfad wurden auf `Inkognito` gezogen, mit Legacy-Fallback für bestehende Notification-Namen.
- Der Source-Ordner wurde in einem separaten Schritt auf `Inkognito/` umgezogen; bewusst erhalten bleiben nur noch Bestandsmigrationspfade wie alte Recents- und ModelCache-Verzeichnisse.

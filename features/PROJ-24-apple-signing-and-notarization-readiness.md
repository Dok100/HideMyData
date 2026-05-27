# PROJ-24 - Apple Signing and Notarization Readiness

**Status**: In Vorbereitung

## Ziel

Die bestehende `Inkognito`-App soll technisch fuer echte Apple-Developer-Distribution vorbereitet werden, ohne dabei die laufende Commercial-Readiness-Bereinigung mit Sparkle-, Lizenz- oder Herkunftsfragen zu vermischen.

## Anlass

Der Projektkontext hat sich geaendert: Es gibt jetzt ein aktives Apple-Developer-Konto. Dadurch werden die bisher nur vorbereiteten Themen Code Signing, Notarisierung, Archivierung und spaetere Distribution konkret umsetzbar.

## Aktueller Befund

Bereits vorhanden:

- automatische Code-Signing-Konfiguration im Projekt
- `DEVELOPMENT_TEAM = 834CMTRWP6`
- Bundle Identifier `de.kernconsulting.inkognito`
- App Sandbox aktiv
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.network.client`
- Sparkle-bezogene Mach-Lookup-Ausnahmen in den Entitlements

Noch offen oder bewusst getrennt:

- produktionsreifer Distribution- und Notarisierungsablauf ist noch nicht dokumentiert
- Archiv-, Export- und Stapler-/Notarytool-Schritte fehlen in der Release-Checkliste
- Sparkle-Historie zeigt noch auf den historischen `HideMyData`-Distributionspfad und bleibt deshalb in `PROJ-22` getrennt
- Release-Artefakte und Changelog sprechen noch nicht konsequent aus einer neuen Apple-Distribution heraus

## Relevante Dateien

- `Inkognito.xcodeproj/project.pbxproj`
- `HideMyData/HideMyData.entitlements`
- `Info.plist`
- `docs/release-checklist.md`
- `features/PROJ-22-sparkle-distribution-reset.md`
- `release/sparkle/appcast.xml`

## Naechste Schritte

1. Signing- und Archive-Readiness fuer `Inkognito` dokumentieren
2. Notarisierungs- und DMG-Distribution als echten Release-Pfad beschreiben
3. Sparkle-Reset gegen die neue Signatur- und Distributionskette abgleichen
4. Danach entscheiden, ob zuerst Direct Distribution oder spaeter Mac App Store vorbereitet wird

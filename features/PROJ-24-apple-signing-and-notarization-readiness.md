# PROJ-24 - Apple Signing and Notarization Readiness

**Status**: Abgeschlossen

## Ziel

Die bestehende `Inkognito`-App soll technisch fuer echte Apple-Developer-Distribution vorbereitet werden, ohne dabei die laufende Commercial-Readiness-Bereinigung mit Sparkle-, Lizenz- oder Herkunftsfragen zu vermischen.

## Anlass

Der Projektkontext hat sich geaendert: Es gibt jetzt ein aktives Apple-Developer-Konto. Dadurch werden die bisher nur vorbereiteten Themen Code Signing, Notarisierung, Archivierung und spaetere Distribution konkret umsetzbar.

## Aktueller Befund

Bereits vorhanden:

- automatische Code-Signing-Konfiguration im Projekt
- `DEVELOPMENT_TEAM = LXXVUJZ9QT`
- `CODE_SIGN_STYLE = Automatic`
- Bundle Identifier `de.okern.inkognito`
- `MARKETING_VERSION = 0.3.0`
- `CURRENT_PROJECT_VERSION = 0.3.0`
- App Sandbox aktiv
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.network.client`
- Sparkle-bezogene Mach-Lookup-Ausnahmen in den Entitlements

Noch offen oder bewusst getrennt:

- produktionsreifer Distribution- und Notarisierungsablauf ist noch nicht dokumentiert
- Archiv-, Export- und Stapler-/Notarytool-Schritte fehlen in der Release-Checkliste
- Sparkle-Historie zeigt noch auf den historischen `HideMyData`-Distributionspfad und bleibt deshalb in `PROJ-22` getrennt
- Release-Artefakte und Changelog sprechen noch nicht konsequent aus einer neuen Apple-Distribution heraus

## Praktischer Befund aus dem ersten Archive-Test

Stand vom `2026-05-31` vor der Team-Umstellung:

- ein erster `xcodebuild archive`-Lauf gegen `output/release/Inkognito.xcarchive` ist noch vor Export und Notarisierung gescheitert
- Fehlerbild: fuer Team `834CMTRWP6` wurde lokal kein passendes Signing-Zertifikat mit privatem Schluessel gefunden
- Xcode meldete konkret: `No signing certificate "Mac Development" found`
- die lokal gefundenen Codesigning-Identitaeten gehoeren derzeit nicht zu `834CMTRWP6`, sondern zu:
  - `Apple Development: oliver.kern@t-online.de (WBZVSYX33J)`
  - `Developer ID Application: Oliver Kern (LXXVUJZ9QT)`

Dieser Befund war der Ausloeser fuer die Umstellung auf das persoenliche Zielbild `LXXVUJZ9QT` plus `de.okern.inkognito`.

Stand nach der Umstellung auf `LXXVUJZ9QT` und `de.okern.inkognito`:

- `xcodebuild archive` nach `output/release/Inkognito.xcarchive` laeuft erfolgreich durch
- `xcodebuild -exportArchive` mit `release/export-options/developer-id.plist` laeuft erfolgreich durch
- die exportierte App traegt danach:
  - `Identifier=de.okern.inkognito`
  - `Authority=Developer ID Application: Oliver Kern (LXXVUJZ9QT)`
  - `TeamIdentifier=LXXVUJZ9QT`
- Gatekeeper lehnt die exportierte App in diesem Zwischenstand erwartbar noch als `Unnotarized Developer ID` ab
- der einfache DMG-Bau nach `output/release/dmg/Inkognito-0.3.0.dmg` funktioniert

Damit ist der technische Pfad bis direkt vor `notarytool submit` jetzt praktisch nachgewiesen.

Aktueller Notarisierungsblocker:

- `xcrun notarytool submit output/release/notary/Inkognito-app.zip --keychain-profile inkognito-notary --wait` startet grundsaetzlich korrekt
- der Lauf scheitert derzeit nicht an Archiv, Signierung oder Bundle Identifier, sondern nur an fehlenden lokal hinterlegten Notary-Credentials
- konkrete Meldung:
  - `No Keychain password item found for profile: inkognito-notary`

Stand nach Anlage des Keychain-Profils `inkognito-notary`:

- App-ZIP-Notarisierung akzeptiert:
  - Submission ID `ef073363-f9a9-4fd5-b2e2-829767b1b7d3`
  - Status `Accepted`
- exportierte App erfolgreich gestapelt
- DMG aus der gestapelten App neu gebaut:
  - `output/release/dmg/Inkognito-0.3.0.dmg`
- DMG-Notarisierung akzeptiert:
  - Submission ID `68699aef-e789-410f-9d3e-c63b1009c456`
  - Status `Accepted`
- finales DMG erfolgreich gestapelt
- lokale Verifikation:
  - `spctl --assess --type execute --verbose output/release/export/Inkognito.app`
    - `accepted`
    - `source=Notarized Developer ID`
  - `xcrun stapler validate output/release/dmg/Inkognito-0.3.0.dmg`
    - `The validate action worked!`

Damit ist der geplante Pfad `Archive -> Export -> App-ZIP notarize -> staple app -> DMG build -> DMG notarize -> staple DMG` einmal erfolgreich abgeschlossen.

Zusatz fuer Folge-Releases:

- der Ablauf ist jetzt auch als wiederholbares Repo-Skript verfuegbar:
  - `bash release/build_and_notarize_dmg.sh`

## Relevante Dateien

- `Inkognito.xcodeproj/project.pbxproj`
- `Inkognito/Inkognito.entitlements`
- `Info.plist`
- `docs/release-checklist.md`
- `docs/apple-direct-distribution.md`
- `features/PROJ-22-sparkle-distribution-reset.md`
- `release/build_and_notarize_dmg.sh`
- `release/export-options/developer-id.plist`
- `scripts/build_release_dmg.sh`
- `release/sparkle/appcast.xml`

## Zielbild fuer den ersten echten Apple-Release

Empfohlener Pfad fuer den naechsten Distributionsschritt:

1. `Inkognito` als signiertes `Archive` bauen
2. daraus eine echte Distributions-App exportieren
3. die exportierte App in ein geplantes Distributions-`dmg` paketieren
4. das Artefakt mit `notarytool` notarisieren
5. `stapler` auf App und DMG anwenden
6. erst danach ueber Sparkle-Integration oder Appcast-Neustart entscheiden

Dieser Pfad ist bewusst als Direct-Distribution-Grundlage formuliert. Er trennt die Apple-Developer-Kette von der spaeteren Sparkle- oder Bestandsmigrationsfrage.

## Konkrete Readiness-Luecken

- kein dokumentierter `Archive -> Export -> Notarize -> Staple`-Ablauf im Repo
- der konkrete DMG-Bau- und Ablagepfad ist noch nicht als Team-Ablauf dokumentiert
- `notarytool`-Profil und Credential-Ablage sind noch nicht als Team-Konvention beschrieben
- Gatekeeper-Pruefung gegen das finale Release-Artefakt fehlt in der Checkliste
- es ist noch nicht festgelegt, ob die Sparkle-bezogenen Entitlements bereits fuer den ersten Direct-Distribution-Release noetig sind
- Sparkle-/Appcast-Neustart bleibt weiterhin getrennt und ist noch offen
- es fehlt noch die Entscheidung, wie dieser notarisierten Pfad spaeter als wiederholbarer Release- oder CI-Ablauf standardisiert wird

## Empfohlene Entscheidungen vor Umsetzung

1. ersten echten Auslieferungspfad als `Direct Distribution` behandeln
2. Sparkle erst in `PROJ-22` wieder aktiv aufgreifen, wenn der notarisierten Basis-Release steht
3. fuer den ersten externen Testlauf ein schlichtes, notarisiertes `dmg` verwenden, statt parallel schon einen kompletten Update-Kanal zu bauen
4. die Release-Checkliste als operative Wahrheit pflegen und `PROJ-24` nur als Vorbereitungs- und Entscheidungsdokument nutzen

## Naechste Schritte

1. `docs/release-checklist.md` mit Signing-, Archive-, Notarisierungs- und Stapler-Schritten erweitern
2. Release-Notizen, Artefaktnamen und Ablageorte fuer echte Distribution festziehen
3. danach `PROJ-22` fuer Sparkle-/Appcast-Neustart konkretisieren
4. optional spaeter denselben Pfad in CI oder ueber einen dedizierten Release-Job automatisieren

## Abgrenzung

Nicht Teil dieses Schritts:

- Umschreiben des historischen `HideMyData`-Appcasts
- finale Sparkle-Migration fuer Bestandsnutzer
- Mac-App-Store-spezifische Vorbereitung
- automatische CI-Distribution

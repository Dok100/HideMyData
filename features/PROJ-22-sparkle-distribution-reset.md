# PROJ-22 – Sparkle-Historie und neue Distribution getrennt vorbereiten

**Status**: In Arbeit

## Ziel

Die bestehende Sparkle-Historie fuer `HideMyData` soll bewusst von einer spaeteren `Inkognito`-Distribution getrennt werden, ohne laufende Bestandsupdate-Pfade versehentlich zu zerstoeren.

## Neuer Ausgangspunkt

Seit `PROJ-24` ist der neue Apple-Direct-Distribution-Pfad fuer `Inkognito` praktisch durchlaufen:

- `Archive -> Export -> App-ZIP notarize -> staple app -> DMG build -> DMG notarize -> staple DMG`
- Bundle Identifier: `de.okern.inkognito`
- Team / Developer-ID-Ziel: `LXXVUJZ9QT`
- wiederholbarer Release-Helfer: `bash release/build_and_notarize_dmg.sh`

Damit ist die Basis fuer einen Sparkle-Neustart nicht mehr hypothetisch, sondern ein bereits funktionierender notarisierten DMG-Pfad.

## Festgelegte Richtung

Fuer den Neustart gilt ab jetzt:

- historischen `HideMyData`-Appcast einfrieren
- alten Pfad nicht still ueberschreiben
- neuen `Inkognito`-Appcast parallel aufsetzen
- neue Sparkle-Artefakte immer aus dem bereits notarisierten DMG-Release-Pfad ableiten

Das bedeutet konkret:

- `release/sparkle/appcast.xml` bleibt vorerst historischer Altpfad
- die neue `Inkognito`-Linie startet ueber eigene Template-/Zieldateien
- eine spaetere Umstellung auf einen echten produktiven Feed darf erst erfolgen, wenn Download-URL, Sparkle-Signatur und Migrationshinweis gemeinsam feststehen

## Schwerpunkte

- alte Sparkle-Artefakte nur historisch sichern, nicht still ueberschreiben
- neuen Appcast- und Artefaktpfad fuer kuenftige `Inkognito`-Releases separat aufsetzen
- Update-Strategie fuer Bestandsnutzer explizit dokumentieren
- sichtbare Herkunft in Release-HTML, Appcast und Download-Zielen konsistent neu fuehren

## Wichtige Vorsichtspunkte

- `release/sparkle/appcast.xml` und `release/sparkle/HideMyData-0.2.0.html` nicht im laufenden Cleanup blind umschreiben
- bestehende Nutzerpfade und alte Signaturen nur migrieren, wenn die Zielstrategie fuer neue Releases feststeht
- Release-Historie, Branding-Wechsel und Lizenzwechsel nicht in einem einzigen riskanten Schritt vermischen

## Erwartete Deliverables

- Entscheidung `historischen Appcast einfrieren / neuen Inkognito-Appcast parallel starten`
- Zielstruktur fuer neue Download- und Appcast-Artefakte
- dokumentierter Migrationshinweis fuer Bestandsnutzer
- aktualisierte Release-Checklist fuer kuenftige Distribution-Releases

## Zielstruktur fuer den Neustart

Empfohlene Trennung:

- historischer Feed:
  - `release/sparkle/appcast.xml`
  - `release/sparkle/HideMyData-0.2.0.html`
- neue `Inkognito`-Linie:
  - `release/sparkle/README.md`
  - `release/sparkle/inkognito-appcast.template.xml`
  - `release/sparkle/inkognito-release-notes.template.html`

Die Template-Dateien sind bewusst noch kein aktiver Feed. Sie definieren nur das neue Format und die benoetigten Platzhalter:

- Download-URL fuer das notarisierten DMG
- Dateigroesse
- `sparkle:version`
- `sparkle:shortVersionString`
- `sparkle:edSignature`
- Release Notes fuer `Inkognito`

## Migrationshaltung fuer Bestandsnutzer

Bis zur bewussten Go-live-Entscheidung gilt:

- Bestandsnutzer des historischen `HideMyData`-Feeds werden nicht automatisch auf den neuen `Inkognito`-Pfad gezogen
- der neue `Inkognito`-Feed wird zuerst als neuer, sauberer Startpunkt behandelt
- ein spaeterer Migrationshinweis soll offen sagen:
  - dass `Inkognito` unter neuer persoehnlicher Apple-Identitaet ausgeliefert wird
  - dass alte `HideMyData`-Artefakte historisch eingefroren bleiben
  - dass bestehende Installationen je nach Altstand eventuell manuelle Neuinstallation oder bewussten Umstieg brauchen

## Relevante Dateien

- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- `release/sparkle/README.md`
- `release/sparkle/inkognito-appcast.template.xml`
- `release/sparkle/inkognito-release-notes.template.html`
- `docs/release-checklist.md`
- `docs/apple-direct-distribution.md`
- `docs/release-draft-0.3.0.md`
- spaetere neue `Inkognito`-Distribution-Artefakte

## Naechste Schritte

1. alte `HideMyData`-Sparkle-Dateien explizit als historisch eingefroren behandeln
2. neue `Inkognito`-Appcast-Templates parallel pflegen
3. fuer den ersten echten Sparkle-Release die Download-URL des notarisierten DMG festlegen
4. Sparkle-Signatur (`sparkle:edSignature`) aus dem finalen Release-Artefakt erzeugen und in den neuen Feed einsetzen
5. erst dann entscheiden, ob und wie Bestandsnutzer aus dem alten Feed auf den neuen Pfad hingewiesen werden

# PROJ-22 – Sparkle-Historie und neue Distribution getrennt vorbereiten

**Status**: Geplant

## Ziel

Die bestehende Sparkle-Historie fuer `HideMyData` soll bewusst von einer spaeteren `Inkognito`-Distribution getrennt werden, ohne laufende Bestandsupdate-Pfade versehentlich zu zerstoeren.

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

## Relevante Dateien

- `release/sparkle/appcast.xml`
- `release/sparkle/HideMyData-0.2.0.html`
- `docs/release-checklist.md`
- `docs/release-draft-0.3.0.md`
- spaetere neue `Inkognito`-Distribution-Artefakte

# Release Draft 0.3.0

## Titel

Inkognito 0.3.0 - Review, Dokumentklassen und Regeln deutlich staerker

## Kurzfassung

Dieses Release macht Inkognito in drei Bereichen deutlich reifer: bessere Erkennung bei realen Dokumentklassen, klarerer Review- und Export-Workflow und produktnaehere eigene Regeln.

## Highlights

- Review mit Seitenstatus, kompakteren Vertrauenshinweisen und schnelleren Sammelaktionen fuer aehnliche Treffer
- staerkere Dokumentklassen-Erkennung fuer Rechnungen, Formulare, Bankseiten, DIN-5008-Geschaeftsbriefe und E-Rechnungen
- bessere Unterdrueckung von Fehlmarkierungen in Rechtstexten und AGB
- menschlichere Export-Zusammenfassung vor und nach dem Speichern
- produktreifere Diagnoseansicht mit klarerem Developer-Modus und JSON-Export
- staerkere Assistenz fuer eigene Regeln mit Vorlagen, Qualitaets-Hinweisen und Treffer-Vorschau im aktuellen Dokument
- konsistentere Sprache, Farben und Trust-Momente in der gesamten App

## Fuer Nutzer wichtig

- automatische Erkennung wirkt robuster bei deutschen Alltagsdokumenten
- unsichere oder auffaellige Stellen sind im Review leichter nachvollziehbar
- aehnliche offene Treffer koennen gesammelt bestaetigt oder abgelehnt werden
- E-Rechnungs-Kontext wird besser verstanden, inklusive ZUGFeRD-, XRechnung- und Leitweg-ID-Markern
- die Zwischenablage-Anonymisierung fuehrt klarer durch Anonymisieren, KI-Nutzung und Rueckfuehrung

## Technische Highlights

- Detection-Regressionen auf `202` Checks erweitert
- neue anonymisierte Fixtures fuer DIN-5008, ZUGFeRD und E-Rechnungs-Feldreferenzen
- Build-Warnungen fuer die ab macOS 26 veraltete `Text + Text`-Komposition entfernt
- aktive Legacy-Migrationspfade bewusst erhalten, obwohl der laufende App-Pfad bereits `Inkognito` spricht

## Verifikation

- `swift scripts/run_detection_regressions.swift`
  - `Detection regressions passed (202 checks)`
- `xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build`
  - `BUILD SUCCEEDED`

## Upgrade-Hinweis

- Bei bestehenden Installationen kann ein einmaliger erneuter Modelldownload noetig sein, falls noch ein aelterer, nicht revisionsgebundener Cache genutzt wurde.

## Interne Einordnung

Dieses Release deckt den Feature-Block `PROJ-8` bis `PROJ-20` ab.

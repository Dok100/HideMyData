# Release Checklist

## Vor dem Release

- `xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build`
- `CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift`
- `swift -module-cache-path /private/tmp/inkognito-swift-module-cache scripts/run_detection_stress_expectations.swift fixtures/detection/inkognito_stress_expectations.json /Users/oliverkern/Downloads` mit aktuellen App-Debug-JSONs aus der Stress-PDF pruefen; Erwartung fuer Release-Kandidaten ist `Failed pages: 0`
- manuelle Pruefung mit mindestens:
  - OCR-lastigem PDF
  - nativem PDF mit Adressblock
  - Bilddatei
  - Clipboard-Flow inklusive Platzhalter-Rueckfuehrung
  - PDF-Export mit anschliessender Vertrauenspruefung in der Sidebar
  - Bild-Export mit anschliessender Vertrauenspruefung in der Sidebar
  - Regeln-Editor mit Vorlagen, Regelqualitaet und Dokumentvorschau
  - Diagnoseansicht inklusive JSON-Export und Developer-Umschalter

## Inhaltlich pruefen

- Branding ueberall auf `Inkognito`
- App-Icon aktuell
- Review-Workflow klar
- Klick auf sichtbare Schwärzung springt zuverlässig zur passenden Review-Kachel
- bei aktivem `Nur offene Treffer` bleibt ein fokussierter bestätigter Treffer für Korrekturen sichtbar
- keine offensichtlichen Diagnose-/Label-Leaks wie `private_person`
- keine funktionalen Blindspots in der Platzhalter-Rueckfuehrung
- Export-Erfolgstext beschreibt klar, dass Schwärzungen eingebrannt wurden
- Vertrauensmodul zeigt keine falschen technischen Zusicherungen
- Metadaten-Bereinigung verhaelt sich passend zur Export-Option
- fehlgeschlagene Öffnen-Aktionen laufen nicht still ins Leere
- ungeeignete Drag-and-drop-Dateien geben einen verständlichen Hinweis
- schwache OCR- oder bildlose PDF-Fälle zeigen einen erklärenden Produktzustand statt leerer Oberfläche
- Clipboard-Anonymisierung reagiert ruhig und verständlich auf leere Zwischenablage oder fehlende Treffer
- fehlgeschlagene Exporte geben eine klare Folgeaktion wie Wiederholen oder Speicherort wechseln
- Legende, Dokument-Highlights und Review-Karten verwenden dieselbe Farblogik für Kategorien
- Source- und Status-Badges in den Review-Karten wirken konsistent zu Status-Pill, Undo-Banner und Export-Vertrauenskarte
- `Eigene Regeln` erklaert sich ohne Technikjargon und zeigt Rueckmeldungen zu Wartungsaktionen in unmittelbarer Naehe der ausloesenden Buttons
- `Technische Ansicht` bleibt lesbar im Dunkelmodus und erklaert ihre Bereiche ueber kurze Info-Hinweise statt rohe Debug-Begriffe
- Seitenstatus in der Sidebar erklaert sich ohne Zusatzwissen und draengt die eigentlichen Treffer nicht aus dem sichtbaren Bereich
- unsichere Treffer sind direkt an der Review-Karte nachvollziehbar markiert, ohne eine zweite Meta-Ebene vor die Trefferliste zu stellen
- `Alle zur Schwaerzung freigeben` benennt die Konsequenz klar und klingt nicht wie `veroeffentlichen`
- die Export-Zusammenfassung nennt geschuetzte Stellen, manuelle Eingriffe und Textqualitaetsrisiken verstaendlich
- der Clipboard-Flow ist in drei Schritten nachvollziehbar und ueberlaedt neue Nutzer nicht mit allen Bereichen gleichzeitig
- die neuen E-Rechnungs- und DIN-5008-Faelle verhalten sich im manuellen Smoke-Test konsistent zu den Regressionen

## Release-Artefakte

- `CHANGELOG.md` aktualisieren
- `README.md`, `docs/architecture.md` und `docs/decision-log.md` gegen den realen Produktstand querlesen
- Release-Text / Highlights formulieren
- fuer wiederholbare Direct-Distribution den Repo-Helfer `bash release/build_and_notarize_dmg.sh` bevorzugen
- Sparkle-/DMG-Artefakte pruefen, falls ein Distribution-Release gebaut wird
- bei neuer Distribution zuerst die getrennte Sparkle-Strategie aus `features/PROJ-22-sparkle-distribution-reset.md` gegen den historischen `HideMyData`-Pfad abgleichen
- Apple-Signing-, Archiv- und Notarisierungsablauf gegen `features/PROJ-24-apple-signing-and-notarization-readiness.md` pruefen, sobald die neue Distribution vorbereitet wird

## Apple-Distribution vorbereiten

- pruefen, dass `Inkognito.xcodeproj` weiter `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = LXXVUJZ9QT` und `PRODUCT_BUNDLE_IDENTIFIER = de.okern.inkognito` verwendet
- sicherstellen, dass fuer die spaetere Auslieferung ein `Developer ID Application`-Zertifikat im Apple-Developer-Konto verfuegbar ist
- Entitlements gegen den echten Auslieferungspfad querlesen:
  - `com.apple.security.app-sandbox`
  - `com.apple.security.files.user-selected.read-write`
  - `com.apple.security.network.client`
  - Sparkle-bezogene Mach-Lookup-Ausnahmen nur behalten, wenn die neue Distribution sie wirklich weiter braucht
- Versionierung fuer den Release-Kandidaten festziehen:
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`
- `notarytool`-Zugang vorbereiten, idealerweise als Keychain-Profil statt mit frei herumliegenden Apple-ID-Credentials

## Archivieren und Exportieren

- in Xcode ein `Archive` fuer `Inkognito` erstellen oder den entsprechenden CI-/CLI-Pfad dokumentiert nachbauen
- das Archiv in `Organizer` auf oeffnende Signing-Probleme, fehlende Entitlements oder Warnungen pruefen
- die App als signierte Distributions-App exportieren, nicht nur als lokale Debug-Build-Kopie
- nach dem Export lokal pruefen:
  - `codesign --verify --deep --strict --verbose=2 Inkognito.app`
  - `spctl --assess --type execute --verbose Inkognito.app`

## Notarisierung und Stapling

- das Distributions-Artefakt fuer Apple vorbereiten:
  - die exportierte `.app` zuerst als `.zip` fuer die App-Notarisierung paketieren
  - nach dem App-Stapling die finale `.app` in das geplante `Inkognito`-`dmg` paketieren
- erst das App-Archiv und danach das finale `dmg` mit `notarytool submit --wait` notarisieren
- nach erfolgreicher Notarisierung das Ergebnis fest mit dem Artefakt verbinden:
  - `xcrun stapler staple Inkognito.app`
  - anschliessend auch das `.dmg` staplen
- danach Gatekeeper lokal gegen das finale Artefakt pruefen, nicht nur gegen die Build-Ausgabe aus `DerivedData`

## Finalen Distributionspfad pruefen

- final entscheiden, ob `0.3.x` zuerst als Direct Distribution ohne Sparkle, mit neuem Sparkle-Pfad oder nur intern verteilt wird
- Dateinamen, Download-Ziele und Release-Text auf `Inkognito` statt historisches `HideMyData` abgleichen
- die lokale `output/release/`-Ausgabe als Build-Artefakt behandeln und nicht in Git einchecken
- erst nach erfolgreich dokumentiertem Notarisierungsdurchlauf `PROJ-22` fuer Appcast- und Bestandsnutzer-Migration weiterziehen

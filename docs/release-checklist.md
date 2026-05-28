# Release Checklist

## Vor dem Release

- `xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build`
- `CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift`
- `swift -module-cache-path /private/tmp/inkognito-swift-module-cache scripts/run_detection_stress_expectations.swift fixtures/detection/inkognito_stress_expectations.json /Users/oliverkern/Downloads` mit aktuellen App-Debug-JSONs aus der Stress-PDF pruefen
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
- Sparkle-/DMG-Artefakte pruefen, falls ein Distribution-Release gebaut wird
- bei neuer Distribution zuerst die getrennte Sparkle-Strategie aus `features/PROJ-22-sparkle-distribution-reset.md` gegen den historischen `HideMyData`-Pfad abgleichen
- Apple-Signing-, Archiv- und Notarisierungsablauf gegen `features/PROJ-24-apple-signing-and-notarization-readiness.md` pruefen, sobald die neue Distribution vorbereitet wird

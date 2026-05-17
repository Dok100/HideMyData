# Release Checklist

## Vor dem Release

- `xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build`
- `CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift`
- manuelle Pruefung mit mindestens:
  - OCR-lastigem PDF
  - nativem PDF mit Adressblock
  - Bilddatei
  - Clipboard-Flow inklusive Platzhalter-Rueckfuehrung
  - PDF-Export mit anschliessender Vertrauenspruefung in der Sidebar
  - Bild-Export mit anschliessender Vertrauenspruefung in der Sidebar

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

## Release-Artefakte

- `CHANGELOG.md` aktualisieren
- Release-Text / Highlights formulieren
- Sparkle-/DMG-Artefakte pruefen, falls ein Distribution-Release gebaut wird

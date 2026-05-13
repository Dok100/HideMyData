# Release Checklist

## Vor dem Release

- `xcodebuild -project Inkognito.xcodeproj -scheme Inkognito -sdk macosx build`
- `CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift`
- manuelle Pruefung mit mindestens:
  - OCR-lastigem PDF
  - nativem PDF mit Adressblock
  - Bilddatei
  - Clipboard-Flow

## Inhaltlich pruefen

- Branding ueberall auf `Inkognito`
- App-Icon aktuell
- Review-Workflow klar
- keine offensichtlichen Diagnose-/Label-Leaks wie `private_person`

## Release-Artefakte

- `CHANGELOG.md` aktualisieren
- Release-Text / Highlights formulieren
- Sparkle-/DMG-Artefakte pruefen, falls ein Distribution-Release gebaut wird

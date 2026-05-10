<div align="center">

<img width="180" height="180" alt="Inkognito" src="HideMyData/Assets.xcassets/AppLogo.imageset/logo.png" />

### Inkognito — Anonymisieren. Direkt auf deinem Mac.

Lokale KI-gestützte Schwärzung sensibler Inhalte für macOS. Gebaut mit [OpenMed](https://github.com/maziyarpanahi/openmed), [MLX-Swift](https://github.com/ml-explore/mlx-swift) und Apple Vision.

![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-007ACC?style=for-the-badge&logo=Xcode&logoColor=white)
![macOS](https://img.shields.io/badge/mac%20os-000000?style=for-the-badge&logo=apple&logoColor=white)

</div>

## Install

Grab the latest `.dmg` from the [Releases](../../releases) page, or build from source - see [Build](#build) below.

https://github.com/user-attachments/assets/353899ca-3810-4fbc-9cbf-45bdf50ec30d

## Features

- **Direkt auf deinem Mac** — Modell, Erkennung und Verarbeitung laufen lokal auf dem Gerät
- **PDF and image input** — both formats share the same detection and redaction pipeline
- **OCR** — Apple Vision handles scanned PDFs, images, and rescues PDFs whose embedded fonts hide text from selection
- **AI detection** — OpenAI `privacy-filter` (MLX 8-bit) catches names, emails, phones, addresses, dates, IDs in context
- **Manually maintained regex** — IBAN, SSN, Personal identifiers, MAC, IPv4/v6, JWT, API keys, crypto wallets and more to come
- **Two redaction styles** — solid black or frosted glass blur
- **Review before final redaction** — automatic hits are marked first and only become final redactions after confirmation
- **Manual editing** — add or remove redaction rectangles by hand before saving
- **Clipboard-Anonymisierung** — kopierten Text lokal anonymisieren und sicher in KI-Tools, E-Mails oder Dokumente einfügen
- **Platzhalter-Rückführung** — KI-Antwort zurückholen und Originalwerte lokal wieder einsetzen
- **Permanent on save** — pages are rasterized and rebuilt - the original text and glyphs are gone, not just hidden
- **Safer PDF sharing** — for confidential exports, use `Black`. The final exported PDF bakes redactions into the saved page instead of leaving removable overlay bars on top

## Clipboard Workflow

Nutze den integrierten Zwischenablage-Workflow, wenn du Texte mit einer KI verbessern willst, ohne Rohdaten weiterzugeben:

1. Text in die Zwischenablage kopieren
2. Vorschau über die App oder den globalen Shortcut öffnen
3. Anonymisierte Version prüfen und in ChatGPT, Claude, Gemini oder ein anderes Tool einfügen
4. KI-Antwort zurück in Inkognito holen
5. Originalwerte lokal aus den Platzhaltern wiederherstellen

Die Platzhalter-Zuordnung bleibt auf deinem Mac. Inkognito lädt keine Originalwerte hoch.

## Review Flow

Für PDFs und Bilder nutzt Inkognito einen zweistufigen Prüf-Workflow:

- automatische Treffer werden zunächst nur farbig markiert
- bestätigte Treffer werden erst danach final geschwärzt oder unscharf exportiert
- abgelehnte Treffer verschwinden wieder
- manuelles `Hinzufügen` / `Entfernen` bleibt jederzeit verfügbar

## Security Notes

- Der stärkste Exportmodus für vertrauliche PDFs ist **`Schwarz`**.
- In diesem Modus wird die finale PDF aus gerenderten Seiten neu aufgebaut, statt nur mit entfernbaren Balken überdeckt zu werden.
- **`Unschärfe`** ist visuell nützlich, aber schwächer als eine vollständige schwarze Schwärzung.
- Gib keine Datei aus dem Zwischenzustand weiter. Nur der finale Export enthält die eingebrannten Schwärzungen.

## Requirements

- macOS 26 or later
- Apple Silicon (the MLX backend does not run on Intel)

## Build

```bash
open HideMyData.xcodeproj
# build & run via Xcode (⌘R)
```

Beim ersten Start lädt Inkognito das Modell (~1.5 GB) von Hugging Face nach `~/Library/Application Support/Inkognito/ModelCache/`.
Die App pinnt das Modell auf eine feste Hugging-Face-Revision statt `main` zu verfolgen, damit spätere Upstream-Änderungen nicht unbemerkt übernommen werden.

## Current Notes

- Die App befindet sich aktuell in einer aktiven UX-/Workflow-Feinabstimmung.
- Einige OCR-lastige Randfälle bei Adressen, Kontodaten und Klassifikation brauchen noch einen weiteren Stabilisierungsschritt.
- Review- und Clipboard-Workflow funktionieren bereits, die Erkennungsqualität wird aber noch weiter nachgeschärft.

## Tech Stack

Swift 6, SwiftUI, MLX-Swift, Apple Vision, PDFKit, OpenMedKit

## License

GPL-3.0

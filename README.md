<div align="center">

<img width="180" height="180" alt="HideMyData" src="HideMyData/Assets.xcassets/AppLogo.imageset/logo.png" />

### Local, AI-powered PII redaction for macOS

Built with [OpenMed](https://github.com/maziyarpanahi/openmed), [MLX-Swift](https://github.com/ml-explore/mlx-swift), and Apple Vision

![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-007ACC?style=for-the-badge&logo=Xcode&logoColor=white)
![macOS](https://img.shields.io/badge/mac%20os-000000?style=for-the-badge&logo=apple&logoColor=white)

</div>

## Install

Grab the latest `.dmg` from the [Releases](../../releases) page, or build from source - see [Build](#build) below.

https://github.com/user-attachments/assets/353899ca-3810-4fbc-9cbf-45bdf50ec30d

## Features

- **Fully local** — model runs on-device, nothing ever leaves your machine
- **PDF and image input** — both formats share the same detection and redaction pipeline
- **OCR** — Apple Vision handles scanned PDFs, images, and rescues PDFs whose embedded fonts hide text from selection
- **AI detection** — OpenAI `privacy-filter` (MLX 8-bit) catches names, emails, phones, addresses, dates, IDs in context
- **Manually maintained regex** — IBAN, SSN, Personal identifiers, MAC, IPv4/v6, JWT, API keys, crypto wallets and more to come
- **Two redaction styles** — solid black or frosted glass blur
- **Review before final redaction** — automatic hits are marked first and only become final redactions after confirmation
- **Manual editing** — add or remove redaction rectangles by hand before saving
- **Clipboard anonymization** — copy text, anonymize it locally, and paste the sanitized version into your AI tool
- **Placeholder restoration** — paste the AI response back and restore the original values locally
- **Permanent on save** — pages are rasterized and rebuilt - the original text and glyphs are gone, not just hidden

## Clipboard Workflow

Use the built-in clipboard workflow when you want to improve a text with an AI assistant without sending raw personal data:

1. Copy a text into the clipboard
2. Open the anonymization preview via the app or the global shortcut
3. Review the anonymized version and copy it into ChatGPT, Claude, Gemini, or another tool
4. Copy the AI response back into HideMyData
5. Restore the original values locally from the generated placeholders

The placeholder mapping stays on your Mac. No original values are uploaded by HideMyData.

## Review Flow

For PDFs and images, HideMyData now uses a two-step review flow:

- automatic detections are shown as colored marks first
- confirmed detections become final black or blurred redactions
- rejected detections are removed again
- manual `Add` / `Remove` editing stays available at all times

## Requirements

- macOS 26 or later
- Apple Silicon (the MLX backend does not run on Intel)

## Build

```bash
open HideMyData.xcodeproj
# build & run via Xcode (⌘R)
```

On first launch, you will be prompted to download the model (~1.5 GB) from Hugging Face into `~/Library/Application Support/HideMyData/ModelCache/`.
The app pins the model to a specific Hugging Face revision instead of tracking `main`, so future upstream changes are not pulled silently.

## Current Notes

- The app is currently in an actively refined UX/workflow phase.
- Some OCR-heavy edge cases around addresses, account data, and classification still need another stabilization pass.
- The current review and clipboard workflows are functional, but detection quality is still being tuned further.

## Tech Stack

Swift 6, SwiftUI, MLX-Swift, Apple Vision, PDFKit, OpenMedKit

## License

GPL-3.0

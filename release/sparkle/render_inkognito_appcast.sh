#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash release/sparkle/render_inkognito_appcast.sh \
    --version 0.3.1 \
    --short-version 0.3.1 \
    --dmg-url https://example.com/Inkognito-0.3.1.dmg \
    --dmg-path output/release/dmg/Inkognito-0.3.1.dmg \
    --ed-signature BASE64_SIGNATURE \
    --notes-file release/sparkle/inkognito-release-notes-0.3.1.html \
    --output release/sparkle/inkognito-appcast-0.3.1.xml

Required:
  --version         Sparkle internal version value
  --short-version   Human-readable version string
  --dmg-url         Final public download URL for the DMG
  --dmg-path        Local path to the final notarized DMG
  --ed-signature    Sparkle edSignature for the final DMG
  --notes-file      HTML file used inside the appcast description
  --output          Output path for the rendered appcast XML

Optional:
  --pub-date        RFC822 publication date. Defaults to current UTC time.
USAGE
}

VERSION=""
SHORT_VERSION=""
DMG_URL=""
DMG_PATH=""
ED_SIGNATURE=""
NOTES_FILE=""
OUTPUT_PATH=""
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --short-version)
      SHORT_VERSION="$2"
      shift 2
      ;;
    --dmg-url)
      DMG_URL="$2"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="$2"
      shift 2
      ;;
    --ed-signature)
      ED_SIGNATURE="$2"
      shift 2
      ;;
    --notes-file)
      NOTES_FILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --pub-date)
      PUB_DATE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for value_name in VERSION SHORT_VERSION DMG_URL DMG_PATH ED_SIGNATURE NOTES_FILE OUTPUT_PATH; do
  if [[ -z "${!value_name}" ]]; then
    echo "Missing required argument: ${value_name}" >&2
    usage >&2
    exit 1
  fi
done

TEMPLATE_PATH="release/sparkle/inkognito-appcast.template.xml"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Release notes file not found: $NOTES_FILE" >&2
  exit 1
fi

DMG_LENGTH_BYTES="$(stat -f%z "$DMG_PATH")"
RELEASE_NOTES_HTML="$(cat "$NOTES_FILE")"
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"

python3 - <<'PY' "$TEMPLATE_PATH" "$OUTPUT_PATH" "$VERSION" "$SHORT_VERSION" "$PUB_DATE" "$DMG_URL" "$DMG_LENGTH_BYTES" "$ED_SIGNATURE" "$RELEASE_NOTES_HTML"
from pathlib import Path
import sys

template_path, output_path, version, short_version, pub_date, dmg_url, dmg_length, ed_signature, release_notes_html = sys.argv[1:]
text = Path(template_path).read_text(encoding="utf-8")
replacements = {
    "{{VERSION}}": version,
    "{{SHORT_VERSION}}": short_version,
    "{{PUB_DATE_RFC822}}": pub_date,
    "{{DMG_URL}}": dmg_url,
    "{{DMG_LENGTH_BYTES}}": dmg_length,
    "{{SPARKLE_ED_SIGNATURE}}": ed_signature,
    "{{RELEASE_NOTES_HTML}}": release_notes_html,
}
for key, value in replacements.items():
    text = text.replace(key, value)
Path(output_path).write_text(text, encoding="utf-8")
PY

echo "Rendered appcast: $OUTPUT_PATH"
echo "DMG length: $DMG_LENGTH_BYTES bytes"

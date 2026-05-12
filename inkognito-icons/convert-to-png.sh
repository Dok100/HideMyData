#!/usr/bin/env bash
# convert-to-png.sh
# Konvertiert alle SVG-Icons in PNGs mit korrekten Pixelgrößen.
# Voraussetzung: librsvg (brew install librsvg)

set -e

cd "$(dirname "$0")"
mkdir -p png

SIZES=(16 32 64 128 256 512 1024)

echo "→ Konvertiere Light-Mode SVGs zu PNG..."
for size in "${SIZES[@]}"; do
    rsvg-convert -w "$size" -h "$size" \
        "light/inkognito-${size}.svg" \
        -o "png/icon_${size}.png"
    echo "  png/icon_${size}.png erstellt"
done

# Apple AppIcon.appiconset Namenskonvention (Mac)
echo ""
echo "→ Kopiere mit Apple-Namen für AppIcon.appiconset..."
mkdir -p AppIcon.appiconset

cp png/icon_16.png    AppIcon.appiconset/icon_16x16.png
cp png/icon_32.png    AppIcon.appiconset/icon_16x16@2x.png
cp png/icon_32.png    AppIcon.appiconset/icon_32x32.png
cp png/icon_64.png    AppIcon.appiconset/icon_32x32@2x.png
cp png/icon_128.png   AppIcon.appiconset/icon_128x128.png
cp png/icon_256.png   AppIcon.appiconset/icon_128x128@2x.png
cp png/icon_256.png   AppIcon.appiconset/icon_256x256.png
cp png/icon_512.png   AppIcon.appiconset/icon_256x256@2x.png
cp png/icon_512.png   AppIcon.appiconset/icon_512x512.png
cp png/icon_1024.png  AppIcon.appiconset/icon_512x512@2x.png

cp Contents.json AppIcon.appiconset/Contents.json

echo ""
echo "✓ Fertig! AppIcon.appiconset/ kann jetzt direkt in Assets.xcassets gezogen werden."

# Inkognito – App Icon Assets

Vollständige Icon-Pipeline für die macOS-App. Jede Größe wurde mit angepasstem
Optical Sizing erstellt, damit auch die kleinen Renderings (16, 32 px) sauber
aussehen und nicht durch reines Herunterskalieren zerfallen.

## Verzeichnisstruktur

```
inkognito-icons/
├── light/                  # Standard-Icons (heller Hintergrund, dunkles Glyph)
│   ├── inkognito-16.svg
│   ├── inkognito-32.svg
│   ├── inkognito-64.svg
│   ├── inkognito-128.svg
│   ├── inkognito-256.svg
│   ├── inkognito-512.svg
│   └── inkognito-1024.svg
├── dark/                   # Dunkle Variante (dunkler Hintergrund, helles Glyph)
│   └── inkognito-*-dark.svg
├── appstore/
│   └── inkognito-1024-square.svg   # Ohne Squircle, falls benötigt
├── Contents.json           # Drop-in für AppIcon.appiconset
├── convert-to-png.sh       # SVG → PNG Konvertierung
└── README.md
```

## Welche Variante für was?

| Anwendung | Datei |
|---|---|
| App-Icon im Dock und Finder | `light/inkognito-*.svg` (alle Größen) |
| App Store Connect Upload | `light/inkognito-1024.svg` (mit Squircle) |
| Marketing-Material auf dunklem Hintergrund | `dark/inkognito-*-dark.svg` |
| Website-Favicon | `light/inkognito-32.svg` oder `64.svg` |
| Menüleiste (Template-Image) | Separat als reines Glyph zu erstellen |

## Schritt 1: SVG zu PNG konvertieren

macOS-Xcode erwartet im Asset Catalog PNG-Dateien (auch wenn neuere Xcode-Versionen
SVGs als Single Size akzeptieren).

### Variante A: Mit rsvg-convert (empfohlen, schnell)

```bash
# Installation falls noch nicht da
brew install librsvg

# Konvertierungs-Skript ausführen
chmod +x convert-to-png.sh
./convert-to-png.sh
```

### Variante B: Mit Inkscape

```bash
brew install --cask inkscape
inkscape light/inkognito-1024.svg --export-type=png --export-filename=icon_512x512@2x.png -w 1024
# ... für jede Größe wiederholen
```

### Variante C: Manuell mit Vorschau.app
Jede SVG öffnen, Exportieren als PNG mit der gewünschten Pixelgröße.

## Schritt 2: AppIcon.appiconset in Xcode anlegen

1. In Xcode: `Assets.xcassets` öffnen
2. Rechtsklick → `App Icons & Launch Images` → `New macOS App Icon`
3. Das neue `AppIcon`-Set öffnen und die generierten PNGs per Drag-and-Drop
   in die passenden Slots ziehen (16pt @1x, 16pt @2x, 32pt @1x, ...)
4. Oder: Den Inhalt des bereitgestellten `Contents.json` mit den PNGs in den
   Ordner `Assets.xcassets/AppIcon.appiconset/` kopieren

## Schritt 3: Im Code referenzieren

In SwiftUI braucht es normalerweise keinen Code, das App-Icon wird automatisch
aus dem Asset-Catalog übernommen. Nur falls Du das Icon innerhalb der App
brauchen solltest (About-Window, Splash):

```swift
Image(nsImage: NSImage(named: "AppIcon")!)
    .resizable()
    .frame(width: 128, height: 128)
```

## Größen-Mapping (Apple Konvention → Pixel)

| Asset-Slot | Pixel-Größe | SVG-Quelle |
|---|---|---|
| 16x16 @1x | 16 × 16 | `inkognito-16.svg` |
| 16x16 @2x | 32 × 32 | `inkognito-32.svg` |
| 32x32 @1x | 32 × 32 | `inkognito-32.svg` |
| 32x32 @2x | 64 × 64 | `inkognito-64.svg` |
| 128x128 @1x | 128 × 128 | `inkognito-128.svg` |
| 128x128 @2x | 256 × 256 | `inkognito-256.svg` |
| 256x256 @1x | 256 × 256 | `inkognito-256.svg` |
| 256x256 @2x | 512 × 512 | `inkognito-512.svg` |
| 512x512 @1x | 512 × 512 | `inkognito-512.svg` |
| 512x512 @2x | 1024 × 1024 | `inkognito-1024.svg` |

## Hinweis zum Optical Sizing

Die Proportionen wurden pro Pixelgröße variiert. Hier die wichtigsten Werte:

| Pixel | Balken-Breite | Balken-Höhe | Stamm-Breite | Stamm-Höhe |
|---|---|---|---|---|
| 1024–256 | 64 | 14 | 20 | 60 |
| 128 | 68 | 16 | 24 | 60 |
| 64 | 70 | 18 | 28 | 62 |
| 32 | 74 | 22 | 32 | 64 |
| 16 | 84 | 26 | 40 | 66 |

Alle Werte beziehen sich auf das viewBox-Koordinatensystem 140 × 140. Bei
kleineren Größen werden Balken und Stamm proportional dicker, damit das
Glyph nicht zerfällt.

## Validierung vor App Store Submission

Apple Notarization und App Store Review prüfen das Icon. Punkte zum Testen:

1. Alle benötigten Größen im `AppIcon.appiconset` vorhanden
2. PNG-Dateien ohne Alpha-Kanal (kein transparenter Hintergrund)
3. Keine ICC-Profile in den PNGs (mit `pngcrush -rem allb` entfernen falls nötig)
4. 1024er Asset hat genau 1024 × 1024 Pixel, nicht mehr, nicht weniger

## Lizenz

Die SVG-Dateien gehören Dir. Die Squircle-Pfad-Approximation ist eine
Standard-Technik, kein geschütztes Asset.

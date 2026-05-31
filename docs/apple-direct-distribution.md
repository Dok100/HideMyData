# Apple Direct Distribution for Inkognito

This document turns `PROJ-24` into a concrete first release path for a notarized `dmg`.

For repeated releases, prefer the repo helper at [build_and_notarize_dmg.sh](/Users/oliverkern/Documents/Projekte/HideMyData/release/build_and_notarize_dmg.sh:1).

## Goal

Build one real Apple Developer distribution artifact for `Inkognito` without mixing in the later Sparkle reset from `PROJ-22`.

The planned first path is:

1. archive the app
2. export a Developer ID signed app
3. package the exported app into a simple `dmg`
4. notarize the app zip and final `dmg`
5. staple app and `dmg`
6. validate the final `dmg` with Gatekeeper

## Prerequisites

- Xcode is signed into the Apple Developer account for team `LXXVUJZ9QT`
- a `Developer ID Application` certificate is available locally
- automatic signing still works for `de.okern.inkognito`
- a `notarytool` keychain profile exists, for example `inkognito-notary`

Example for creating the keychain profile once:

```bash
  xcrun notarytool store-credentials "inkognito-notary" \
  --apple-id "<apple-id>" \
  --team-id "LXXVUJZ9QT" \
  --password "<app-specific-password>"
```

Prefer a keychain profile over passing Apple credentials inline in later commands.

## Standard artifact paths

Use repo-local output paths so archive, export, and `dmg` runs are easy to inspect and clean up:

- archive: `output/release/Inkognito.xcarchive`
- exported app: `output/release/export/Inkognito.app`
- app zip for notarization: `output/release/notary/Inkognito-app.zip`
- dmg: `output/release/dmg/Inkognito-0.3.0.dmg`

## One-command release path

After the `inkognito-notary` keychain profile exists, the whole release path can be run through:

```bash
bash release/build_and_notarize_dmg.sh
```

Optional version override:

```bash
bash release/build_and_notarize_dmg.sh 0.3.1
```

Optional custom notary profile:

```bash
KEYCHAIN_PROFILE=inkognito-notary bash release/build_and_notarize_dmg.sh
```

The script performs:

1. archive
2. export
3. app zip creation
4. app notarization
5. app stapling
6. dmg build
7. dmg notarization
8. dmg stapling

## 1. Build the archive

The following manual sections remain useful for understanding and troubleshooting the scripted flow.

```bash
xcodebuild \
  -project Inkognito.xcodeproj \
  -scheme Inkognito \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$PWD/output/release/Inkognito.xcarchive" \
  archive
```

If automatic signing needs to talk to Apple during the archive, rerun with `-allowProvisioningUpdates`.

## 2. Export the signed app

Use the repo template at [release/export-options/developer-id.plist](/Users/oliverkern/Documents/Projekte/HideMyData/release/export-options/developer-id.plist:1).

```bash
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/output/release/Inkognito.xcarchive" \
  -exportOptionsPlist "$PWD/release/export-options/developer-id.plist" \
  -exportPath "$PWD/output/release/export"
```

This should produce:

- `output/release/export/Inkognito.app`

## 3. Verify the exported app locally

```bash
codesign --verify --deep --strict --verbose=2 "$PWD/output/release/export/Inkognito.app"
spctl --assess --type execute --verbose "$PWD/output/release/export/Inkognito.app"
```

The exported app should pass before the `dmg` is built.

## 4. Build the DMG

Use the helper script at [scripts/build_release_dmg.sh](/Users/oliverkern/Documents/Projekte/HideMyData/scripts/build_release_dmg.sh:1).

```bash
bash scripts/build_release_dmg.sh \
  "$PWD/output/release/export/Inkognito.app" \
  "$PWD/output/release/dmg/Inkognito-0.3.0.dmg" \
  "Inkognito"
```

The helper creates a simple staging layout with:

- `Inkognito.app`
- `Applications` symlink

That is enough for a first external test release.

## 5. Notarize

The safe first pass is:

1. zip the exported app for notarization
2. notarize that zip
3. staple the exported app
4. build the final `dmg` from the stapled app
5. notarize the final `dmg`
6. staple the final `dmg`

### Zip the app for notarization

```bash
mkdir -p "$PWD/output/release/notary"
ditto -c -k --keepParent \
  "$PWD/output/release/export/Inkognito.app" \
  "$PWD/output/release/notary/Inkognito-app.zip"
```

### App notarization via zip

```bash
xcrun notarytool submit \
  "$PWD/output/release/notary/Inkognito-app.zip" \
  --keychain-profile "inkognito-notary" \
  --wait
```

```bash
xcrun stapler staple "$PWD/output/release/export/Inkognito.app"
```

### Build the final DMG from the stapled app

```bash
bash scripts/build_release_dmg.sh \
  "$PWD/output/release/export/Inkognito.app" \
  "$PWD/output/release/dmg/Inkognito-0.3.0.dmg" \
  "Inkognito"
```

### DMG notarization

```bash
xcrun notarytool submit \
  "$PWD/output/release/dmg/Inkognito-0.3.0.dmg" \
  --keychain-profile "inkognito-notary" \
  --wait
```

```bash
xcrun stapler staple "$PWD/output/release/dmg/Inkognito-0.3.0.dmg"
```

## 6. Final Gatekeeper check

Always validate the final user-facing artifact, not just the app in DerivedData:

```bash
spctl --assess --type open --verbose "$PWD/output/release/dmg/Inkognito-0.3.0.dmg"
```

Optionally also mount the `dmg`, copy the app to `/Applications`, and open that installed copy once on a second machine or a clean local test user.

## First practical release decisions

- keep the first `dmg` visually simple
- do not wire Sparkle into this first external test path yet
- keep artifact naming on `Inkognito`
- only move to `PROJ-22` after one complete `archive -> export -> dmg -> notarize -> staple` run is documented as successful

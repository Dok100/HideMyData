# Sparkle Restart Notes

This folder now has two distinct roles:

## 1. Historical `HideMyData` feed

These files remain frozen for legacy reference and possible compatibility work:

- `appcast.xml`
- `HideMyData-0.2.0.html`

Do not silently overwrite them while preparing the new `Inkognito` distribution path.

## 2. New `Inkognito` feed templates

The new `Inkognito` Sparkle line should be derived from the notarized DMG release path validated in `PROJ-24`.

Use these template files as the starting point for a future real feed:

- `inkognito-appcast.template.xml`
- `inkognito-release-notes.template.html`
- `render_inkognito_appcast.sh`

Before publishing a live Sparkle release, fill in:

- the final public DMG URL
- the DMG byte length
- the final `sparkle:version`
- the final `sparkle:shortVersionString`
- the Sparkle `edSignature`
- release notes text for the specific `Inkognito` version

The current templates are intentionally not active feeds.

## Suggested release flow

1. Build and notarize the final DMG via `bash release/build_and_notarize_dmg.sh`.
2. Create or adapt HTML release notes from `inkognito-release-notes.template.html`.
3. Generate the Sparkle `edSignature` for the final DMG with your Sparkle signing tool.
4. Render a concrete appcast from the template:

```bash
bash release/sparkle/render_inkognito_appcast.sh \
  --version 0.3.1 \
  --short-version 0.3.1 \
  --dmg-url https://downloads.example.com/Inkognito-0.3.1.dmg \
  --dmg-path output/release/dmg/Inkognito-0.3.1.dmg \
  --ed-signature BASE64_SIGNATURE \
  --notes-file release/sparkle/inkognito-release-notes-0.3.1.html \
  --output release/sparkle/inkognito-appcast-0.3.1.xml
```

5. Publish the generated appcast and matching DMG together.

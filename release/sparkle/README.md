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

Before publishing a live Sparkle release, fill in:

- the final public DMG URL
- the DMG byte length
- the final `sparkle:version`
- the final `sparkle:shortVersionString`
- the Sparkle `edSignature`
- release notes text for the specific `Inkognito` version

The current templates are intentionally not active feeds.

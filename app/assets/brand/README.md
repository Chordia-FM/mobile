# Brand assets

Copied from the frontend's `public/`, which generates them from
`frontend/src/components/brand/mark.ts` via `scripts/generate-brand-assets.ts`. That file is the one
definition of the mark — the record, the C, the label ring — and every rendering of it comes from
those same numbers.

**Do not touch these up by hand.** A hand-patched icon is how the launcher icon quietly stops
matching the product. When the mark changes, re-run the frontend's generator, copy the two files
here again, and regenerate the launcher icons:

    dart run flutter_launcher_icons

| File | Source | Used for |
|---|---|---|
| `icon.png` | `logo512.png` | every layer: the legacy square icon, the adaptive foreground, and the Android 13+ monochrome layer |

The **unpadded** render is deliberate. `flutter_launcher_icons` insets the foreground by 16% to build
the safe zone itself, so handing it `logo-maskable.png` — which already carries 10% padding — stacks
the two and leaves the mark at about half the icon, noticeably smaller than everything else in the
launcher.

The adaptive icon's background is a flat `#040208` — `ChordiaColors.pane`, the app's own canvas — so
the icon reads as part of the app rather than as a sticker on top of it.

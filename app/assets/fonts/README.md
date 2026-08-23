# Manrope + Fraunces

The web client's two faces, carried over so the phone reads as the same product. `frontend/src/styles.css`
sets `--font-sans: "Manrope Variable", …` on `body` and `.display-title { font-family: "Fraunces Variable", … }`
on every page H1; the app shipped neither, so every string rendered in Roboto/SF.

## Where these come from

Upstream `google/fonts`, the same source `@fontsource-variable/{manrope,fraunces}` (the web's
dependency) is generated from:

- `ofl/manrope/Manrope[wght].ttf` — Manrope 4.504
- `ofl/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf` — Fraunces 1.000

Verified rather than assumed: the sample glyph outlines in each variable font are byte-identical to the
ones in the woff2 files sitting in `frontend/node_modules/@fontsource-variable/*/files/`, so the phone
is drawing the *same* font the browser draws, not a lookalike release.

Both are SIL Open Font Licence 1.1 — `Manrope-OFL.txt` and `Fraunces-OFL.txt` are the licences, kept
here because the OFL requires them to travel with the files. They are not listed in `pubspec.yaml`, so
they live in the repo without being bundled into the app.

## Why static instances and not the variable fonts

Flutter applies a variable font's `wght` axis through `TextStyle.fontVariations`, not through
`fontWeight` — a widget that says `fontWeight: FontWeight.w600` against a bare variable file gets the
font's *default* instance with a synthetic smear on top. Manrope's default instance is ExtraLight (200)
and Fraunces' is Black (900), so shipping the variable files would have rendered the entire app at the
wrong weight while looking, in code, exactly right. There are 57 `fontWeight:` call sites in `lib/` and
none of them should have to know which file backs the family.

So each weight the web actually uses is instanced to its own static TTF. Counting the Tailwind classes
in `frontend/src`: `font-medium` (500) x208, `font-semibold` (600) x140, `font-bold` (700) x81, plus the
400 that `body` inherits. Fraunces only ever appears on `.display-title`, at `font-bold` and (in
`ErrorState.tsx`) `font-semibold`, hence two weights rather than four.

Fraunces' other three axes are pinned to what a browser resolves them to on this site:

- `opsz` 30. CSS defaults `font-optical-sizing: auto`, which feeds the *rendered pixel size* into the
  axis. Below `sm`, which is the only column that matters here, the display titles are `text-3xl` (30px)
  at nine of the nineteen call sites, `text-2xl` at five and `text-4xl` at three — 30 is the size the
  phone actually draws most often, not a midpoint someone liked.
- `SOFT` 0 and `WONK` 1, the font's own defaults, because nothing in the stylesheet sets
  `font-variation-settings` and so the browser leaves them there. `WONK` is on upstream, which is why
  the `g` has its swash — that is the intended Fraunces, not a mistake.

## Regenerating

Needs `fonttools[woff]` (the `woff` extra is only for re-running the woff2 comparison above):

```python
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

for w, sub in ((400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")):
    inst = instancer.instantiateVariableFont(
        TTFont("Manrope[wght].ttf"), {"wght": w}, inplace=False, updateFontNames=True
    )
    inst.save(f"Manrope-{sub}.ttf")

for w, sub in ((600, "SemiBold"), (700, "Bold")):
    inst = instancer.instantiateVariableFont(
        TTFont("Fraunces[SOFT,WONK,opsz,wght].ttf"),
        {"wght": w, "opsz": 30, "SOFT": 0, "WONK": 1},
        inplace=False,
        updateFontNames=False,  # Fraunces' STAT table has no axis value at opsz 30
    )
    # then set name IDs 1/2/4/6/16/17 to "Fraunces" / sub, and OS/2.usWeightClass to w
    inst.save(f"Fraunces-{sub}.ttf")
```

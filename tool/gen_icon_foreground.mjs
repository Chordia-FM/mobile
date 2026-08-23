// Renders the transparent launcher-icon foreground from the brand mark.
//
// Android composites an adaptive icon from a foreground and a background, so the foreground has to
// be TRANSPARENT outside the mark. The PNGs the frontend publishes are both deliberately opaque —
// `logo512.png` is the square app icon and `logo-maskable.png` is a PWA maskable icon, which the
// spec requires to fill its canvas — so neither can be used here: an opaque foreground hides the
// background layer entirely and the launcher shows a flat near-black tile.
//
// `favicon.svg` is the one published asset with no background, so it is the source. Its ink is a
// CSS variable behind a `prefers-color-scheme` query, which a rasteriser does not evaluate — it
// would resolve to the light-mode value and draw a near-black mark on our near-black background.
// The dark ink is therefore substituted in before rendering.
//
// Run from the mobile repo root, with the frontend checked out beside it (resvg lives there):
//
//   node tool/gen_icon_foreground.mjs
//
// Then regenerate the launcher icons:
//
//   cd app && dart run flutter_launcher_icons

import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";

const FRONTEND = "../frontend";
const SOURCE = `${FRONTEND}/public/favicon.svg`;
const OUT = "app/assets/brand/icon-foreground.png";

/** `INK_DARK` in the frontend's generator: the mark as it is drawn on a dark surface. */
const INK = "#f0eff5";

/** Generous, because the launcher tool insets what it is given to make the safe zone. */
const SIZE = 1024;

const require = createRequire(`${process.cwd()}/${FRONTEND}/package.json`);
let Resvg;
try {
  ({ Resvg } = require("@resvg/resvg-js"));
} catch {
  console.error(
    `Could not load @resvg/resvg-js from ${FRONTEND}/node_modules.\n` +
      `Check out the frontend beside this repo and run its install first.`,
  );
  process.exit(2);
}

const svg = readFileSync(SOURCE, "utf8")
  // The whole point: resolve the variable rather than leaving it to a cascade that will not run.
  .replace(/<style>[\s\S]*?<\/style>/, "")
  .replaceAll("var(--ink)", INK);

if (svg.includes("var(--ink)")) {
  console.error("The ink variable survived substitution; the source's shape changed.");
  process.exit(2);
}

const png = new Resvg(svg, {
  fitTo: { mode: "width", value: SIZE },
  // No background: transparency is the entire reason this file exists.
}).render().asPng();

writeFileSync(OUT, png);
console.log(`Wrote ${OUT} (${SIZE}x${SIZE}, transparent)`);

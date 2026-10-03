# OnTimely app icon

Generated with the built-in imagegen tool.

Selected master: `OnTimely-icon-master.png`

The macOS PNG exports live in `Design/AppIcon.appiconset/`. They preserve the generated transparency and are resampled with macOS `sips`.

The app bundles `OnTimely/Resources/OnTimely.icns`, converted from all ten PNG exports with Apple's `iconutil`. Both Debug and Release explicitly reference this file with `CFBundleIconFile`. This avoids the placeholder icon seen when loading the asset catalog icon on this Mac.

## Generation prompt

```text
Use case: logo-brand
Asset type: production macOS app icon for OnTimely, a very minimal native deadline reminder app.
Primary request: Create one polished, original app icon that combines time and task completion in a single clear symbol. The app captures tasks, reminds the user to start, checks again at latest safe start, and reminds them to submit.
Scene/backdrop: A single centered macOS rounded-square icon tile, with genuinely transparent pixels outside the tile. Square 1024 × 1024 artwork, straight-on, no perspective; the tile fills roughly 82–86% of the canvas, with balanced transparent margins and gently continuous rounded corners.
Subject: A bold, simple circular clock outline with two connected hands forming a subtle check mark. Keep the clock/check silhouette large and immediately readable at 16–32 pixels. Three small restrained timing marks suggest the app's three deadline stages. All details must be optically balanced, crisp, and simple.
Style/medium: Refined native macOS utility icon; clean geometric graphic with a little soft dimensional polish, a matte pale neutral tile and the restrained blue accent already present in the app's native controls. Broad clean shapes, generous negative space, very subtle surface shading only. Calm, precise, memorable.
Constraints: One icon only, no text, no letters, no numbers, no wordmark, no surrounding scene, no mockup, no border frame around the canvas, no watermark. Preserve real alpha outside the rounded-square tile. No busy details, rainbow colors, large gradients, glossy plastic, dramatic shadows, or extra objects.
```

## Final cleanup prompt

```text
Use case: precise-object-edit
Asset type: final macOS application icon for OnTimely.
Input image: edit target, the generated blue clock/checkmark on a pale rounded-square tile.
Change only the outer edge and transparent background: remove every stray speckle, white fringe, irregular protrusion and detached pixel outside the icon tile. Make the tile's outer contour a perfectly smooth, clean macOS rounded-square curve with crisp antialiasing. Outside the tile must be fully transparent, including the canvas corners. No outer glow and no drop shadow outside the tile.
Preserve the exact clock/checkmark symbol, its three timing marks, blue accent, pale tile, internal shading, alignment, and relative scale. Keep the whole tile centered with balanced transparent margins on a square canvas. No text or extra elements. Output a complete, visible full-color icon with real alpha transparency.
```

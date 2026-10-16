# Imported design and native icon

`claude-design/` preserves the supplied **Grouply Mobile App Prototype.zip** as a reference. The latest design is `Grouply App.dc.html`; `support.js` is its browser runtime, not a native iOS dependency. The older v1/v2 HTML and uploaded documents are historical material, not instructions to execute. The native app uses SwiftUI; it does not embed the HTML in a WebView.

The source prototype v3.1 establishes the four tabs and Soft Future visual direction. Corrected business rules live in `docs/` v1.3 and the tested native store.

## Icon

Workspace asset: `Grouply/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024 × 1024 PNG, raster).

Generated using the built-in Image Generation tool and resized for the iOS asset catalog. The app's standard interface icons use SF Symbols.

Final generation prompt:

> Create one premium flat iOS app icon for GROUPLY, a calm student group-work collaboration app with Soft Future visual identity. Square full bleed opaque mint #C9F2D6 background with very subtle lighter mint central tone. Center a single crisp dark charcoal #202124 symbol: three friendly abstract human heads above three interlocking simple U shaped shoulder forms, representing a group working together, central figure slightly higher. Tiny lavender #DED2FF circular accent behind the right shoulder. Simple geometric rounded shapes, vector-like flat raster rendering, polished restrained native Apple app feel, clean negative space, thick even forms, high contrast recognizable at 40px, no typography, no letters, no text, no mockup, no border, no drop shadow, no gradients on the symbol, no 3D, no gloss, no pre-rounded outside corners: fill the entire square canvas, OS supplies the outer corner mask. Output a single 1024 square icon.

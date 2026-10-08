# Bundled assets

The app bundles its visual assets; screens do not require loading photo or font URLs at runtime.

## Typography

Manrope variable font from the [Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/manrope), licensed under the SIL Open Font License. The original license is included at `assets/fonts/OFL.txt`.

## Food photography

Unsplash source image URLs used for the local illustration assets:

- `salad.jpg`: https://images.unsplash.com/photo-1512621776951-a57141f2eefd
- `bowl.jpg`: https://images.unsplash.com/photo-1546069901-ba9599a7e63c
- `breakfast.jpg`: https://images.unsplash.com/photo-1490645935967-10de6ba17061
- `burger.jpg`: https://images.unsplash.com/photo-1568901346375-23c9450c58cd
- `pancakes.jpg`: https://images.unsplash.com/photo-1567620832903-9fc6debc209f
- `curry.jpg`: https://images.unsplash.com/photo-1603894584373-5ac82b2ae398
- `momo.jpg`: https://images.unsplash.com/photo-1534422298391-e4f8c172dddb

These illustrate the meal categories; they are not evidence of food-recognition results or exact ingredients. In particular, the momo illustration contains assorted dumplings, and the curry illustration is not a measured regional recipe.

## Branding and icons

`assets/images/kayleo-mark.svg` is a code-authored K-and-leaf mark matching the user's supplied logo direction, with a near-black K, lime dot and cream background. `assets/images/kayleo-icon.png` is its bundled raster version for About. Android/iOS/macOS/Windows/web launcher assets are rendered from the same geometry by `tools/generate_brand_assets.py` using Pillow. In-app icons use Flutter's bundled Material icon font. No remote font service or image-generation dependency is required.

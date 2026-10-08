# Product and implementation research

Research completed 6 October 2026. The supplied nine-page blueprint was read as product context; it did not override the user's request to build a prototype without login or registration.

## Core finding

The strongest product loop is **input → targeted clarification → editable estimate → confirmed local meal → immediate daily feedback**. Building that loop as one shared workflow prevents camera, text, and voice from becoming inconsistent products. Recognition and nutritional calculation are separate responsibilities: a model may identify food; structured portion data should determine the numbers.

## Primary sources and resulting decisions

### Meal scanning and correction

[MyFitnessPal: How to use the Meal Scanner](https://support.myfitnesspal.com/hc/en-us/articles/360045761612-How-to-use-the-Meal-Scanner) describes photo-based suggestions, serving adjustments, adding missed foods, and a final logging step. This supports keeping recognition results editable and making confirmation explicit. **Design inference:** fewer screens and a shared review surface make correcting an estimate more practical. Kayleo adds a short clarification stage for ambiguous rice portions or curry preparation, following the blueprint's focus on uncertainty and nutritional impact.

### Useful tracking and reporting

[Cronometer's feature overview](https://cronometer.com/features/) presents food logging, nutrient tracking, biometrics, and reports. **Design inference:** the daily view should answer immediate questions while trends live in a separate destination. Kayleo shows the logging action, current nutrition, recent meals, and hydration on Today, with 7/30-day energy views and weight history in Progress.

### Food provenance and portion calculations

[USDA FoodData Central documentation](https://fdc.nal.usda.gov/data-documentation/) distinguishes analyzed foundation foods, survey foods, branded label records, and legacy references. [The downloadable datasets](https://fdc.nal.usda.gov/download-datasets/) provide structured formats suitable for a future local catalog, and [the API guide](https://fdc.nal.usda.gov/api-guide/) documents the server lookup path. **Architecture decision:** each food records nutrients per 100 g, serving grams, aliases, and source text. The client computes nutrients from grams instead of accepting an arbitrary model calorie total. The prototype catalog is a small illustrative fixture; it is not a download of a verified USDA database. Production needs exact food identifiers, licenses, versions, and regional recipe validation.

### Adult target estimation

[The original Mifflin–St Jeor paper](https://pubmed.ncbi.nlm.nih.gov/2305711/) is the reference for the resting-energy equation. [NIDDK's Body Weight Planner](https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner) describes personalized adult planning and its limitations. **Prototype decision:** collect a compact adult profile, estimate maintenance with a documented activity multiplier, allow target editing, and use modest goal adjustments. Do not treat this static equation as the NIDDK dynamic model. The 1,500–4,500 kcal UI range is a prototype guardrail, not a universal medical recommendation. The prototype excludes under-18 onboarding and does not model pregnancy or clinical needs.

### Responsive Flutter interfaces

[Flutter's adaptive design practices](https://docs.flutter.dev/ui/adaptive-responsive/best-practices) discuss window sizes, navigation, and input methods. [Flutter's accessibility design guidance](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling) reinforces legibility and scaling. **Implementation decision:** a sidebar at desktop width, five primary destinations on mobile, secondary destinations in Settings, responsive column layouts, accessible text/controls, and persistent bottom-sheet confirmation. Short desktop windows hide the optional premium promotion so navigation fits. The hero grows with text scaling. Main pages scroll rather than clipping content.

### Local persistence

[SharedPreferences package documentation](https://pub.dev/packages/shared_preferences) documents a small cross-platform key-value store. **Prototype decision:** serialize the shared state to a versioned record, queue writes, preserve corrupt data in a recovery backup, and offer a JSON export. **Production limitation:** this storage is not a suitable encrypted transactional health database. SQLite/Drift with migrations and an explicit sync queue would be the next foundation.

### Camera and photo behavior

[ImagePicker documentation](https://pub.dev/packages/image_picker) documents mobile capture, gallery selection, permissions, desktop restrictions, and temporary camera files. **Implementation decision:** support native mobile capture and selection, explain unavailable desktop capture, downsize images on supporting platforms, keep bytes in the local meal record, and limit upload size. Photo recognition is visibly simulated; a user's own image requires a meal description. No image is uploaded to a cloud model.

### Voice and unsupported devices

[SpeechToText documentation](https://pub.dev/packages/speech_to_text) documents platform permissions and device/browser recognition. **Implementation decision:** ask for speech access on user action, let transcripts remain editable, expose a useful typed/example fallback, and route the transcript through the same meal engine. Native speech can depend on the provider's connectivity; the UI does not claim all voice recognition is offline.

### Export and sharing

[SharePlus documentation](https://pub.dev/packages/share_plus) documents native sharing and web fallback behavior. **Implementation decision:** export JSON using a proper file name and offer a weekly consistency share that omits weight and calorie details. A real Chrome check confirmed the fallback file download. The app never automatically sends user data or community content to a server.

## Information architecture

The blueprint's camera-first intent is represented by a prominent capture card and a persistent capture destination. Today is the landing surface because it also gives the user useful feedback immediately after logging. The raised center mobile camera button opens the immersive camera directly. The desktop Scan food destination retains the capture hub, where the sample plate opens its real camera inline. This is a prototype design choice, not a claim that a live camera preview is running at launch.

A seven-step first-run experience introduces the value, captures the minimum profile, and presents an editable starting plan. Sample exploration is optional and visibly labeled. It avoids collecting any account credentials.

The interface uses forest green for primary actions, cream for background, lime for small wins, and restrained orange/blue for macro and hydration distinctions. Food photos and bundled typography give it a cohesive identity. Numbers consistently say estimated nutrition; assumptions and data sources remain inspectable.

## Retention choices

Streaks count days with meals recorded. Badges reward consistency, reaching a user-selected protein target, and hydration habits. The community challenge asks users to log a meal each day; there is no low-calorie leaderboard. Weekly averages exclude days without meal records and explicitly warn that incomplete logs can lower averages. Insights and food suggestions are transparent rule-based summaries, not an unconnected chatbot.

## Production integration sequence

1. Replace SharedPreferences with an encrypted local database, migrations, photo storage limits, and restore/import support.
2. Import a versioned authoritative nutrition catalog and validate regional dishes by recipe and serving conventions.
3. Define a model-agnostic recognition adapter that returns candidate foods, portions, assumptions, and uncalibrated uncertainty separately from nutrient values.
4. Evaluate vision/text models on a representative meal set. Calibrate confidence and rank clarification by expected calorie/macronutrient impact.
5. Add a backend sync service and an explicit retry queue when authentication is introduced in a later scope. This prototype intentionally has no account system.
6. Add real barcode scanning/product lookup, notification scheduling, and opt-in health-platform integrations.
7. Verify store subscriptions and purchase restoration server-side before activating billing.
8. Add real community APIs, privacy controls, reporting, moderation, and consent-aware uploads after the private logging loop is validated.

The prototype exercises the product behavior now while keeping these external dependencies explicit.

## Kayleo refinement — 6 October 2026

The rebrand preserves the working local state, nutrient calculations and shared meal review. The normal phone layout puts a compact consumed-calorie ring beside remaining/target values so Scan food, Type it and Tell Kayleo are available on the first viewport. Full-screen scanning uses a dark forest environment; captured photos return to the warm description/review flow. There is no vision inference service, and no detection claims are made for real photos.

The accessibility work follows [Flutter's accessibility guidance](https://docs.flutter.dev/ui/accessibility): labeled controls, readable text, large touch areas and checks at increased text size. [Flutter's scaling migration guidance](https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration) informed use of TextScaler and 200% regression coverage. [MediaQuery.disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html) is read explicitly by the ring, onboarding animations and voice pulse. [ThemeData extensions](https://api.flutter.dev/flutter/material/ThemeData/extensions.html) provide semantic card/surface tokens for the staged dark-mode rollout. These are implementation choices based on the documentation, not claims that every future screen is already dark-mode complete.

## Reference-based appearance refinement

The user's screen montage guided the cream/forest surfaces, food-photo collages and the centered daily ring followed by three compact logging tiles and protein/carbs/fats bars. A saved Light/Dark/System preference changes the entire MaterialApp theme. Theme-aware surfaces extend to sheets and charts, while camera/voice stay immersive. Secondary text was darkened after an automated contrast check; both palettes meet 4.5:1 for primary/secondary text on their main surfaces and primary button labels. The user's later K-and-leaf logo reference replaces the earlier temporary ring emblem.

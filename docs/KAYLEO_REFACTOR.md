# Kayleo implementation report

The existing Flutter application has been refactored in place into **Kayleo**. The store-facing title is **Kayleo: AI Calorie Tracker**. No project rebuild, authentication flow or new runtime dependency was introduced.

## Audit and preservation

Architecture: `KayleoApp` loads `AppState`, then splash/onboarding or `AppShell`. The shell keeps adaptive desktop/sidebar and mobile navigation. `ChangeNotifier` and shared meal models remain the state layer; JSON in SharedPreferences remains persistence. A deterministic `MealEngine` and illustrative local food catalog calculate nutrition. Photo, text and device voice use the same editable confirmation pipeline. The real camera has serialized initialization/disposal, permission handling and background/resume behavior.

Previous styling lived in `core/ui.dart`, with Manrope, reusable panels, buttons, photos, tags and rings. All features were inspected: onboarding, Today, capture/logging, diary/saved meals, Progress, You/settings and community. Old branding appeared in the app root, wordmark, permissions/errors, onboarding/settings/premium copy, sharing/export, native labels, web metadata and documentation. The main risks were persistence compatibility, camera lifecycle changes, smaller viewports, and text scaling. Those workflows were preserved and checked.

## Files modified

| Area | Files / groups |
|---|---|
| App and shared components | `lib/main.dart`; `lib/core/ui.dart`, `app_state.dart`, `nutrition_view.dart` |
| Feature screens | `lib/features/shell.dart`, `dashboard.dart`, `logging.dart`, `meal_camera.dart`, `onboarding.dart`, `diary.dart`, `progress.dart`, `settings.dart`, `community.dart` |
| Tests | `test/widget_test.dart`, `test/meal_camera_test.dart` |
| Android | App manifest; launch background XML in drawable/drawable-v21; launcher PNGs in all five mipmap densities |
| iOS | Runner Info.plist; LaunchScreen storyboard; all existing app icon and launch image PNGs |
| macOS | Runner Info.plist; AppInfo.xcconfig; product references in project.pbxproj and Runner.xcscheme; seven app icon PNGs |
| Windows / Linux | Windows Runner.rc, window title in main.cpp and app_icon.ico; Linux runner window title |
| Web | index.html, manifest.json, favicon and four app icons |
| Project/docs | pubspec description, README, RESEARCH, WORKFLOWS, ASSETS and VERIFICATION |

`docs/CHANGE_MANIFEST.json` contains the exact saved source/asset paths and hashes.

## Files created

- `lib/theme/kayleo_colors.dart`, `kayleo_typography.dart`, `kayleo_spacing.dart`, `kayleo_radius.dart`, `kayleo_theme.dart`.
- `test/accessibility_test.dart` and `test/theme_test.dart`.
- `assets/images/kayleo-mark.svg`, `assets/images/kayleo-icon.png` and `tools/generate_brand_assets.py`.
- Android 12+ warm splash resources in `values-v31/styles.xml` and `values-night-v31/styles.xml`.
- `metadata/store_listing.en.json`, this report, and `docs/CHANGE_MANIFEST.json`.

The unused botanical `assets/images/nouri-mark.svg` was removed. Existing food photography and Manrope were retained.

## Branding and design system

The wordmark is lowercase **kayleo.**, with its period in lime and an accessible Kayleo label. The launcher mark is the supplied K-and-leaf direction: a near-black K with a leaf upper arm and bright lime dot on cream. A code-authored SVG produces consistent Android, Apple, Windows and web icons; the bundled PNG appears in About. In-app copy uses Kayleo; descriptions/store metadata use the longer title where appropriate. App labels, camera permissions/errors, export filenames and sharing text are rebranded. Splash uses a cream background and a fast wordmark-only Flutter frame; web and native launch surfaces match the palette.

The palette is centralized: cream `#F7F5ED`, forest `#163E2D`, lime `#B8E36B`, sage `#E4EBDD`, ink `#17231D`, muted olive `#626E64` (darkened for readable secondary text). Protein is `#F07894`, carbs `#F1B963`, and fat `#9A7DDD`; macro labels and values remain readable independently of color. Shared typography, radii, spacing, button sizing and semantic card surfaces are reusable tokens. Repeated feature spacing/radii use those tokens. Chart geometry and camera dimensions remain local where they describe actual layout behavior.

`KayleoRing` replaces the generic ring, with progress/activity states and subtle transitions that honor reduced motion. `KayleoDot` signals calm status. Existing Panel, SectionTitle, EmptyState, MealRow and NutrientProgressRow components were reused rather than duplicated. Shared headings/tags wrap; navigation adapts to larger labels.

## UX changes

Today now presents a personal greeting, consumed/remaining/target calories, then Scan food, Type it and Tell Kayleo. The centered ring shows consumed and remaining calories, with the daily target below. Three equal logging tiles and compact full-width protein/carbs/fats bars remain visible on a normal phone before the meals section. Large-text layouts grow vertically. Hydration, consistency and an insight derived from actual logged protein remain below. Decorative hero photography and speculative recommendations were removed from Home.

Diary uses “Your food story.” and “Search your meals...”. Dates, filters, edits, individual foods, meal totals and all nutrition calculations remain. Progress keeps four nutrient averages and selectable 7/30-day charts with correct units/targets, weight/movement, consistency and a data-derived weekly review, with fewer summary cards. You uses grouped rows for goals, diet preferences, measurements, notifications, appearance and privacy, plus units/export/reset, saved meals and community entry points; premium is Kayleo+ and remains a clear concept preview. Repetitive “little” copy and sparkle/eco branding were removed.

## Camera and logging

The raised mobile center action is circular lime with a forest camera icon. Tapping it opens a full-screen dark camera directly. Controls include Close, Gallery, a real shutter, lens switching and Type/Camera/Voice modes, plus a flash button only when the camera provider supports it. Capture stops the camera, with Retake/Use photo controls; accepting returns to the warm meal input/review. Android system-bar styling follows the dark camera surface. Gallery cancellation and switching logging mode release/reopen hardware as appropriate. The sample plate still opens its camera inline.

The review shows Kayleo sees for parsed foods, Estimated nutrition, Ready to add and Add meal. Meaningful rice/curry uncertainty keeps the existing targeted questions. Voice opens a forest listening screen with concentric rings and an editable transcript. Listening is shown only while the actual device speech provider is active; the pulse stops for reduced motion. Review uses rounded estimated-total and macro cards with short colored accents. No fake detection, generated confidence or new backend was added.

## ASO configuration

Draft store text is in `metadata/store_listing.en.json`: exact store title, subtitle, short description, positioning keywords and an accurate prototype description. Web title/manifest use the store-facing title. Android/iOS launcher labels remain simply Kayleo. Nothing was submitted to an app store. Marketing claims must be reviewed against the actual shipped integrations before submission.

## Compatibility references intentionally retained

`AppState.storageKey = nouri_state_v1` and `AppState.recoveryKey = nouri_recovery_backup_v1` remain to preserve existing logs and recovery backups. Recovery tests intentionally contain those strings. The browser storage prefix is owned by SharedPreferences. Renaming these keys without a migration would hide existing user data.

The Dart package `calorie_app`, Android application ID/package, Apple bundle IDs, Linux application ID and Windows binary/internal filename remain stable technical identifiers. They are not visible Kayleo branding. The internal Dart app class was safely renamed to KayleoApp because it has no persisted/external contract. macOS product references were aligned with its display product name so the scheme and test host point at Kayleo.app.

## Dark theme and technical debt

Light, Dark and System are available under You → Appearance, switch immediately and persist across launches. Forest-toned backgrounds, warm-white text, lime actions and semantic card/soft/border surfaces apply across routes, onboarding, charts and settings sheets. Camera and voice intentionally use dark immersive surfaces in either appearance. Status/navigation bar styling follows the active theme. Switching appearance preserves the current route and an open meal draft; resetting local data restores Light.

Tests verify both palettes' primary/secondary text and button-label contrast, narrow layouts, doubled text, appearance persistence and unchanged legacy meal records. Large-text regression coverage does not replace a physical TalkBack/VoiceOver audit. SharedPreferences remains prototype storage. Broad localized strings are not yet in ARB files. The resolved share_plus plugin emits a future Kotlin Gradle migration warning; it does not prevent the current Android build.

The workspace uses cloud placeholders, which previously interrupted builds. Verification used an intact local copy of the same sources; changes are saved back to the original workspace. The local preview serves that verified release build.

## Mock / limited integrations

- Sample photo results are preset demonstrations. Real photos require a description; no vision model is connected.
- Text uses a deterministic local parser and a small illustrative catalog; regional/composite nutrition is estimated.
- Voice uses the actual device/browser speech provider, whose permissions/connectivity vary by platform.
- Barcode is sample/manual lookup; no live barcode scanner or product database.
- Community, premium/billing, notification scheduling, cloud sync and wearable connections remain preview or unconnected features.
- Progress/weekly review use actual locally stored records; the optional seeded sample week is labeled throughout.

## Validation

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --dart-define=CAPTURE_PREVIEWS=true`: **42 tests passed**. Coverage includes calculations, legacy persistence/recovery, onboarding, all routes, food edits, history dates, all four nutrients, empty/over-target records, camera lifecycle, gallery cancellation and large-text workflows.
- Large-text coverage: 320×640 settings/onboarding/community and 360px core routes/camera at 200%, with Manrope and reduced motion.
- Release web build: passed.
- Android debug APK build: passed, including updated branding/icons and Android 12+ splash configuration.
- Release Chrome check: passed immersive capture/retake, text confirmation, reload persistence, all four chart selectors/30-day range and Kayleo-named JSON export, with no JavaScript page errors. Screenshots are listed in VERIFICATION.md.

No physical camera/microphone or signed iOS/macOS release test was performed. Chrome used a simulated media device, with no personal account/data.

## Recommended next steps

1. Run the rebuilt app on physical Android/iOS devices, including denied/revoked permissions, notches and system text settings.
2. Run physical-device camera/speech and TalkBack/VoiceOver checks before distribution.
3. Connect validated vision and nutrition data, then calibrate uncertainty and review store claims/screenshots.
4. Introduce encrypted storage/migrations before expanding to accounts, cloud sync or production subscriptions.

## Reference refinement — 7 October 2026

The supplied screen montage informed the food-photo collages, voice waveform and typed-meal onboarding panels; greeting/ring/logging/macro hierarchy; flatter navigation with one raised Scan action; simpler Diary/Progress/You headings; and cream/forest Appearance modes. Functional meal editing, uncertainty questions, data export and existing nutrition calculations remain available.

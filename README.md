# Kayleo — AI Calorie Companion prototype

A complete, interactive Flutter prototype based on **AI_Calorie_Companion_Product_Blueprint.pdf**. No login or registration. A warm cream, forest-green, and lime interface adapts to phones, tablets, and desktop windows.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Other supported development targets:

```sh
flutter run -d macos
flutter run                     # select an attached Android/iOS device
```

To serve the release web build:

```sh
flutter build web --release --no-web-resources-cdn
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:8765. A preview server is running there at handoff. It is local to this computer.

## Explore

1. Watch the branded splash, then complete the seven-step onboarding. Or choose **Explore with sample data** for a clearly marked, populated sample week.
2. From **Today**, choose **Scan food**, **Type it**, or **Tell Kayleo**.
3. Try **Rice and chicken curry**. Answer the rice portion and preparation questions, edit the ingredients, and confirm the meal. The diary and totals update immediately.
4. Try **Two eggs and avocado toast**, **8 chicken momo**, or **I had a veg burger with five ounces of French fries**. Amounts are calculated from structured food portions.
5. Uploaded photos are kept locally, if enabled. Describe their contents to create an estimate; sample photo scans demonstrate the future recognition workflow.
6. In **Saved meals**, review and log a usual. With suitable history, text or voice can also use **same breakfast as yesterday**.
7. Add water, record weight and movement, and explore **Progress** and the weekly review. The charts and review use your actual local records.
8. Visit **You / Settings** to adjust your profile, targets, units, reminder preferences, photo retention, privacy, export, or reset. Mobile users also find Saved meals and Community here.
9. Explore the **Community preview**, join local sample groups, cheer a post, leave a local comment, or share a saved-meal preview. Nothing is posted to a server.

## Working features

- K-and-leaf launcher logo, branded web/native startup and minimal Flutter splash.
- Premium cream and dark forest themes; choose Light, Dark or System under You → Appearance. Your choice is saved, and theme changes preserve meal drafts.
- Three introduction screens, goals, validated adult body profile, activity and food preferences, personalized starting targets.
- Live in-app camera with capture, retake, lens switching, and photo selection; device speech input with useful fallbacks, local text parsing, sample barcode lookup, food search, manual label nutrition.
- Shared meal review workflow with targeted clarification, deterministic per-100-g calculations, editable foods, portions, meal name, date/time, notes, and calculation assumptions.
- Create, edit, repeat, delete, and undo deletion of meals; save reusable templates.
- Local persistence of profile, diary, water, weight, activity, preferences, community interactions, and premium-preview state.
- Daily calorie/macronutrient totals with separate protein, carbs, and fats progress bars; date-aware diary and filters; 7/30-day calorie and macro charts with individual targets; weight trend, logging streaks, habit badges, and rule-based weekly reviews.
- In-app reminders, privacy controls, data/photo deletion, JSON export through native sharing or browser download, quiet-hour preferences.
- Opt-in community UI and a premium-plan preview; no billing and no authentication.
- Bundled food photography and Manrope font, accessible Flutter semantics, native permission descriptions, and responsive navigation.

## Prototype boundaries

**Photo recognition is a clearly labeled demo.** Uploaded images are not analyzed by a trained model. Text uses a deterministic local parser and a small food library. Unknown food can be entered manually; no invented nutrition is returned for an unmatched description. Composite and regional recipes are illustrative estimates, not a verified nutrition database.

Speech recognition uses the device/browser provider and may require connectivity. The sample plate’s camera button opens a live camera in the same meal panel on Android, iOS, and web. Capture a photo, retake it, or use it in your meal log. The main photo action starts the camera directly. The camera stops when you capture, close, leave the panel, or background the app. Web camera access requires HTTPS or localhost; native desktop builds offer photo selection and a browser/phone fallback. Device camera/microphone permissions are requested only when their controls are used. Actual hardware permission flows need testing on physical devices.

Live barcode scanning/database lookup, cloud sync, production AI, subscriptions, scheduled/background notifications, wearable integrations, and a live social network require later integrations. No API key, server, payment, or account is needed to use this prototype.

Local storage uses SharedPreferences (browser localStorage on web), which is appropriate for this small prototype. It is not encrypted, transactional production health storage. Use an encrypted database with migrations, an authenticated sync service, and explicit data-retention policies before production. Photos are limited to 2 MB per upload to keep local storage manageable. Browsers may clear their storage.

Once the app is loaded, local meal, water, weight, and activity logging needs no network. Assets and web engine resources are bundled in the release build. Installing a web offline cache is a separate deployment task; this prototype does not promise a cold browser launch without a server or cached app.

## Verification

```sh
flutter analyze
flutter test
flutter test --dart-define=CAPTURE_PREVIEWS=true
flutter build web --release --no-web-resources-cdn
```

The suite covers portion calculations, high-impact questions, natural language units/times, regional matches, manual nutrition, edits, persistence/recovery, target safeguards, full onboarding, screen navigation, hydration, unknown foods, and short desktop/mobile layouts. The optional capture flag writes screenshots to `output/previews/`.

A real Chrome release-build check also exercised meal clarification and saving, navigation, reload persistence, JSON download, community interactions, and mobile navigation without JavaScript errors.

## Project structure

- `lib/theme/` — centralized Kayleo colors, type, spacing, radii and light/dark theme architecture.
- `lib/core/` — state persistence, meal parser/clarification engine, reusable UI and dialogs.
- `lib/data/` — shared data models and the illustrative local food catalog.
- `lib/features/` — onboarding, app shell, daily view, diary, saved meals, logging, progress, community, and settings.
- `test/` — data/engine and end-to-end Flutter widget tests.
- `docs/RESEARCH.md` — primary-source research and the design/architecture decisions it informed.
- `docs/WORKFLOWS.md` — screen map and prototype integration status.
- `assets/` — bundled imagery, app mark, font and font license.
- `output/previews/` — rendered desktop/mobile screen captures.

Photo sources and the Manrope license are recorded in `docs/ASSETS.md`.

The Kayleo rebrand, compatibility decisions, design tokens, store metadata, and remaining integration work are recorded in [docs/KAYLEO_REFACTOR.md](docs/KAYLEO_REFACTOR.md).
# calorie-app

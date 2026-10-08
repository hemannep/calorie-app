# Kayleo verification — 7 October 2026

## Final automated checks

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --dart-define=CAPTURE_PREVIEWS=true`: **42 tests passed**.
- `flutter build web --no-pub --release --no-web-resources-cdn`: passed.
- `flutter build apk --no-pub --debug`: passed; updated APK is `build/app/outputs/flutter-apk/app-debug.apk`.
- Native XML, Apple plists, launch storyboard, macOS scheme and JSON metadata parse successfully.

Tests preserve calculation, persistence/recovery, manual nutrition, meal editing, historic dates, diary controls, onboarding and navigation. The nutrient checks cover protein/carbs/fats/calories, averages, targets, 7/30-day ranges and empty/over-target values.

Seven camera tests cover inline sample capture, retake/use, lens switching, close, denial/retry, background/resume, exit during initialization, and immersive scanning. Gallery cancellation releases then reopens the camera. Switching to Type/Voice releases hardware and returns to the warm input flow. Camera audio remains disabled. Supported flash toggles call the camera provider; an unsupported flash control is hidden. The narrow immersive test switches Voice → Camera and captures successfully. Camera layout at 360×640/200% text remains usable.

Large-text regression tests load Manrope and MaterialIcons. At 320×640 with 200% text and reduced motion, all onboarding steps, choice semantics, profile/target/privacy/reminder/premium/About sheets, units, preferences, community membership/challenge/likes and persistence pass. Today/Diary/Progress/You also pass at 360px and 200% in both themes. Four new theme tests verify contrast, immediate appearance switching without losing an open draft, saved appearance, legacy records and reset behavior. Settings/onboarding/community run in Light and Dark at 320×640/200%. Normal phone Today keeps Scan food, Type it and Tell Kayleo fully above the bottom navigation. Desktop routes pass at 1440×1000; previous short-desktop coverage remains.

## Final release-browser check

The release build was exercised in an isolated local Chrome context with a simulated media device, sample data and no personal account. The run confirmed:

- Camera starts only after the Scan action; all three Home logging actions are visible initially.
- The raised center button's upper edge opens the immersive scanner.
- Capture releases video tracks, Retake opens them again, and Use photo returns to the warm description flow.
- Text rice/curry logging asks targeted details, previews the meal and saves it.
- Reload restores the confirmed 237 g rice portion through the unchanged legacy storage key.
- Diary navigation, all four nutrient chart selectors and the 30-day range work.
- Export downloads a `kayleo-backup-...json` file containing the saved meal.
- Small-phone navigation renders; no JavaScript page errors occurred.

Light/dark reference captures use the `reference-light-...` and `reference-dark-...` filenames, alongside all three food-led onboarding intros. Final browser images in `output/previews/` include `live-kayleo-today.png`, `live-kayleo-scanner.png`, `live-kayleo-photo-description.png`, `live-kayleo-meal-review.png`, `live-kayleo-diary.png`, `live-kayleo-progress.png` and `live-kayleo-small-phone.png`. Widget captures also include large-text primary screens.

The local preview at http://127.0.0.1:8765 serves the verified release build. Because cloud-backed workspace placeholders previously interrupted tools, builds/checks used a complete local verification copy; source/configuration/asset changes and the APK were saved back to the original workspace.

## Practical limits

Physical Android/iOS camera, microphone permissions and native speech were not exercised. No signed iOS/macOS distribution build was run. Photo recognition, live barcode/product lookup, scheduled notifications, purchases, cloud sync, wearables and live community remain demo/unconnected integrations. Composite recipe values require validated production nutrition data.

The Android build emits the existing share_plus warning about a future Kotlin plugin migration. The current build succeeds on Flutter 3.47.6 / Dart 3.13.5.

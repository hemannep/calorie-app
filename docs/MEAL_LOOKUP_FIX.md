# Text/voice food lookup and Android build fixes

8 October 2026

## Behavior

Typing a meal or editing a voice transcript and choosing **Understand my meal** now checks the local catalog, then searches **both Open Food Facts and USDA FoodData Central** for foods outside that catalog. Previously, this action used only the 30-entry local catalog; the separate Food Search screen was the only route to external databases.

The new planner separates foods connected by common conjunctions or commas, removes common logging phrases/times/quantities from search queries, and preserves the original meal date/time and input mode. It avoids reducing an unfamiliar composite dish such as chicken biryani to a generic chicken match. Known local meals continue through their existing offline clarification flow.

Database results show names, sources and per-100-unit nutrition. Exact dish names rank above related names. Users choose a matching recipe/product, enter the amount eaten, complete any missing required label values, and then review the combined meal before saving. Explicit grams, ounces and ml are carried into matching; piece counts are not converted to guessed weights. Mass and volume are kept separate.

An outage in one provider does not hide the other's results. Saved API food snapshots can supply matching records when offline. No-result cases list foods not included and offer manual recovery; they do not invent calories or silently omit unmatched foods. Canceling selection preserves the draft and allows retry. Source snapshots and portions persist with the meal, so future calculations do not require another network request. Storage failures remain visible instead of displaying success.

The planner is a deterministic English parser, not a general language model. Very unusual phrasing may need a simpler food name. External datasets can contain different recipes or brands; selection and portion review remain essential. Unknown foods require connectivity unless a matching snapshot was previously saved. The default USDA `DEMO_KEY` remains subject to provider quotas; production can supply `--dart-define=USDA_API_KEY=...`.

## Android fixes

The supplied build failure was caused by duplicate generated resource names, including `launch_background 2.xml`, inside `build/app/intermediates`. The source resource filenames were valid. Generated build output and the stalled project Gradle cache were cleared.

`share_plus` was upgraded to 13.3.1 and built-in Kotlin enabled. Its support is documented in the [sharing plugin changelog](https://pub.dev/packages/share_plus/changelog) and [Flutter migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers). The vendored Java plugin now targets Java 17, matching the app; an unused raw-generic helper causing unchecked-operations messages was removed. Existing analyzer import diagnostics were corrected.

## Validation

Regression coverage includes natural speech queries, mixed local/unknown dishes, composite dish preservation, measured units/fractions, provider failures, exact-name ranking, required missing nutrient values, cancellation/retry, text and voice-transcript confirmation, nutrient scaling and JSON reload.

The Android integration test sends only the public sample query `samosa`. On the connected Samsung SM S948B, both live providers returned records and the integration test passed. It does not access microphone/camera or modify diary records. Device speech transcription itself was not newly tested.

The Desktop workspace has intermittent macOS cloud-placeholder read failures (`Operation timed out`, errno 60), including source files and generated Gradle caches. A complete source copy was read successfully into `/private/tmp/kayleo-meal-fix` without fallback replacements, and automated validation/builds use that local copy. This filesystem issue is separate from Dart/Android correctness; keeping development source and generated caches in a fully local folder avoids this class of interruption.

Final results are recorded in the handoff. The delivered APK is a debug build, not a signed store release. Passing tests does not establish universal nutrition or model accuracy.
